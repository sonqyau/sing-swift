import Foundation
import Logging
import NIO
import NIOTransportServices

@MainActor
public final class SocksInboundAdapter: InboundNetworkAdapter {
    public let tag: String
    private let configuration: InboundConfiguration
    private let eventLoopGroup: any EventLoopGroup
    private let logger: Logger
    private var serverChannel: (any Channel)?
    private var isRunning = false

    public init(
        tag: String,
        configuration: InboundConfiguration,
        eventLoopGroup: any EventLoopGroup,
        logger: Logger,
    ) {
        self.tag = tag
        self.configuration = configuration
        self.eventLoopGroup = eventLoopGroup
        self.logger = logger
    }

    public func start() async throws {
        guard !isRunning else {
            throw AdapterError.configurationError("Adapter already running")
        }

        logger.info("Starting SOCKS inbound adapter on \(configuration.listenAddress):\(configuration.port)")

        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(ChannelOptions.backlog, value: 256 as Int32)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1 as Int32)
            .childChannelInitializer { (channel: any Channel) -> EventLoopFuture<Void> in
                let socksInbound = SocksInbound(logger: self.logger)
                let promise: EventLoopPromise<Void> = channel.eventLoop.makePromise(of: Void.self)
                Task { @MainActor in
                    do {
                        try await socksInbound.handle(context: channel.pipeline.context, connection: channel)
                        promise.succeed()
                    } catch {
                        promise.fail(error)
                    }
                }
                return promise.futureResult
            }

        serverChannel = try await bootstrap
            .bind(host: configuration.listenAddress, port: configuration.port)
            .get()
        isRunning = true
        logger.info("SOCKS inbound adapter started")
    }

    public func stop() async throws {
        guard isRunning else { return }

        logger.info("Stopping SOCKS inbound adapter")

        if let channel = serverChannel {
            try await channel.close()
            serverChannel = nil
        }

        isRunning = false
        logger.info("SOCKS inbound adapter stopped")
    }

    public func serve() async throws {
        guard isRunning else {
            throw AdapterError.configurationError("Adapter not running")
        }

        logger.debug("SOCKS inbound adapter is serving connections")
    }
}
