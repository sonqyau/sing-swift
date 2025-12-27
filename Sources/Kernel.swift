import Foundation
import Logging
import NIO
import NIOTransportServices

public actor Kernel {
    private let eventLoopGroup: any EventLoopGroup
    private let adapterManager: AdapterManager
    private let router: DefaultRouter
    private let logger: Logger
    private var isRunning = false
    private var startTime: Date?
    private var configuration: Configuration?

    public init(logger: Logger = Logger(label: "kernel")) {
        self.eventLoopGroup = NIOTSEventLoopGroup()
        self.logger = logger
        self.adapterManager = AdapterManager(eventLoopGroup: eventLoopGroup, logger: logger)
        self.router = DefaultRouter(rules: [], defaultOutbound: "direct")
    }

    deinit {
        Task { [eventLoopGroup] in
            try? await eventLoopGroup.shutdownGracefully()
        }
    }

    public func start(configuration: Configuration) async throws {
        guard !isRunning else {
            throw KernelError.alreadyRunning
        }

        logger.info("Starting kernel")
        self.configuration = configuration

        try await createOutboundAdapters(configuration.outbounds)

        try await createInboundAdapters(configuration.inbounds)

        try await adapterManager.startAll()

        isRunning = true
        startTime = Date()
        logger.info("Kernel started")
    }

    public func stop() async throws {
        guard isRunning else {
            throw KernelError.notRunning
        }

        logger.info("Stopping kernel")

        try await adapterManager.stopAll()

        isRunning = false
        startTime = nil
        configuration = nil

        logger.info("Kernel stopped")
    }

    public func status() -> KernelStatus {
        KernelStatus(
            isRunning: isRunning,
            startTime: startTime,
            version: Version.current,
        )
    }

    public func route(destination: String, port: Int) async -> String {
        await router.route(destination: destination, port: port)
    }

    private func createInboundAdapters(_ inbounds: [InboundConfiguration]) async throws {
        logger.info("Creating \(inbounds.count) inbound adapters")

        for inbound in inbounds {
            do {
                _ = try await adapterManager.createInboundAdapter(configuration: inbound)
                logger.info("Created inbound adapter: \(inbound.tag)")
            } catch {
                logger.error("Failed to create inbound adapter \(inbound.tag): \(error)")
                throw error
            }
        }
    }

    private func createOutboundAdapters(_ outbounds: [OutboundConfiguration]) async throws {
        logger.info("Creating \(outbounds.count) outbound adapters")

        for outbound in outbounds {
            do {
                _ = try await adapterManager.createOutboundAdapter(configuration: outbound)
                logger.info("Created outbound adapter: \(outbound.tag)")
            } catch {
                logger.error("Failed to create outbound adapter \(outbound.tag): \(error)")
                throw error
            }
        }
    }

    public func connect(to destination: String, port: Int) async throws -> any Channel {
        guard isRunning else {
            throw KernelError.notRunning
        }

        let outboundTag = await route(destination: destination, port: port)
        logger.info("Routing connection to \(destination):\(port) via \(outboundTag)")

        guard let outboundAdapter = await adapterManager.getOutboundAdapter(tag: outboundTag) as? DirectOutboundAdapter else {
            throw KernelError.configurationError("Outbound adapter not found: \(outboundTag)")
        }

        return try await outboundAdapter.connect(to: destination, port: port)
    }

    public func connectUDP(to destination: String, port: Int) async throws -> any Channel {
        guard isRunning else {
            throw KernelError.notRunning
        }

        let outboundTag = await route(destination: destination, port: port)
        logger.info("Routing UDP connection to \(destination):\(port) via \(outboundTag)")

        guard let outboundAdapter = await adapterManager.getOutboundAdapter(tag: outboundTag) as? DirectOutboundAdapter else {
            throw KernelError.configurationError("Outbound adapter not found: \(outboundTag)")
        }

        return try await outboundAdapter.connectUDP(to: destination, port: port)
    }
}

public struct KernelStatus: Sendable {
    public let isRunning: Bool
    public let startTime: Date?
    public let version: String

    public init(isRunning: Bool, startTime: Date?, version: String) {
        self.isRunning = isRunning
        self.startTime = startTime
        self.version = version
    }
}

public enum KernelError: Error, LocalizedError {
    case alreadyRunning
    case notRunning
    case unsupportedProtocol(String)
    case configurationError(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "Kernel is already running"
        case .notRunning:
            "Kernel is not running"
        case let .unsupportedProtocol(type):
            "Unsupported protocol: \(type)"
        case let .configurationError(message):
            "Configuration error: \(message)"
        }
    }
}
