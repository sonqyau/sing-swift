import Foundation
import Network

public final class Kernel {
    private let runtime = KernelRuntime()

    public init() {}

    public func start(configuration: Configuration) async throws {
        try await runtime.start(configuration: configuration)
    }

    public func stop() async {
        await runtime.stop()
    }

    public func sessionCount() async -> Int {
        await runtime.sessionCount
    }
}

actor KernelRuntime {
    private enum Lifecycle {
        case idle
        case starting
        case running
        case stopping
    }

    private var lifecycle: Lifecycle = .idle
    private var logger: Logging?
    private var dnsResolver: DNSResolver?
    private var router: Router?
    private var outboundRegistry: [String: OutboundEndpoint] = [:]
    private var inboundEndpoints: [InboundEndpoint] = []
    private var sessions: [UUID: Session] = [:]

    var sessionCount: Int { sessions.count }

    func start(configuration: Configuration) async throws {
        guard lifecycle == .idle else {
            throw Error.alreadyRunning
        }

        lifecycle = .starting

        let logger = Logging(identity: configuration.identity)
        let resolver = DNSResolver(configuration: configuration.dns, logger: logger)

        try resolver.warmUp()

        guard let fallback = configuration.routes.first?.outbound ?? configuration.outbounds.first?.tag else {
            lifecycle = .idle
            throw Error.invalidConfiguration("missing fallback route")
        }

        let router = Router(routes: configuration.routes, fallback: fallback)

        var outboundRegistry: [String: OutboundEndpoint] = [:]
        for outbound in configuration.outbounds {
            outboundRegistry[outbound.tag] = try OutboundEndpoint(configuration: outbound)
        }

        var inboundEndpoints: [InboundEndpoint] = []
        for inbound in configuration.inbounds {
            let endpoint = try InboundEndpoint(configuration: inbound, logger: logger) { [weak self] connection, pipeline in
                guard let self else {
                    connection.cancel()
                    return
                }
                Task.detached { [weak self] in
                    guard let self else {
                        connection.cancel()
                        return
                    }
                    await self.accept(connection: connection, pipeline: pipeline)
                }
            }
            inboundEndpoints.append(endpoint)
        }

        self.logger = logger
        self.dnsResolver = resolver
        self.router = router
        self.outboundRegistry = outboundRegistry
        self.inboundEndpoints = inboundEndpoints

        for endpoint in inboundEndpoints {
            endpoint.start()
        }

        lifecycle = .running
        logger.log(.info, "kernel running")
    }

    func stop() async {
        guard lifecycle == .running || lifecycle == .starting else {
            return
        }

        lifecycle = .stopping

        for endpoint in inboundEndpoints {
            endpoint.stop()
        }
        inboundEndpoints.removeAll()

        for session in sessions.values {
            session.cancel()
        }
        sessions.removeAll()

        router = nil
        outboundRegistry.removeAll()
        dnsResolver = nil

        logger?.log(.info, "kernel stopped")
        logger = nil

        lifecycle = .idle
    }

    private func accept(connection: NWConnection, pipeline: PipelineConfiguration) async {
        guard lifecycle == .running, let router, let logger, let dnsResolver else {
            connection.cancel()
            return
        }

        do {
            let outboundTag = try router.resolve(pipeline: pipeline)

            guard let outbound = outboundRegistry[outboundTag] else {
                throw Error.outboundMissing(outboundTag)
            }

            let outboundConnection = try outbound.makeConnection(
                overrideTarget: pipeline.targetOverride,
                resolver: dnsResolver
            )

            let session = Session(
                inbound: connection,
                outbound: outboundConnection,
                logger: logger,
                throttle: pipeline.throttle
            ) { [weak self] id in
                guard let self else { return }
                Task { await self.removeSession(id: id) }
            }

            sessions[session.id] = session
            session.start()

            logger.log(.debug, "session \(session.id.uuidString)")
        } catch {
            logger.log(.error, "session error \(error)")
            connection.cancel()
        }
    }

    private func removeSession(id: UUID) {
        sessions[id]?.cancel()
        sessions.removeValue(forKey: id)
    }
}
