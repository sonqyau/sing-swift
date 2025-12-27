import Foundation
import Logging
import NIO
import NIOTransportServices

@MainActor
public final class DirectOutboundAdapter: OutboundNetworkAdapter {
    public let tag: String
    private let configuration: OutboundConfiguration
    private let eventLoopGroup: any EventLoopGroup
    private let logger: Logger
    private let directOutbound: DirectOutbound
    private var isRunning = false

    public init(
        tag: String,
        configuration: OutboundConfiguration,
        eventLoopGroup: any EventLoopGroup,
        logger: Logger,
    ) {
        self.tag = tag
        self.configuration = configuration
        self.eventLoopGroup = eventLoopGroup
        self.logger = logger
        self.directOutbound = DirectOutbound(eventLoopGroup: eventLoopGroup, logger: logger)
    }

    public func start() async throws {
        guard !isRunning else {
            throw AdapterError.configurationError("Adapter already running")
        }

        logger.info("Starting Direct outbound adapter")
        isRunning = true
        logger.info("Direct outbound adapter started")
    }

    public func stop() async throws {
        guard isRunning else { return }

        logger.info("Stopping Direct outbound adapter")
        isRunning = false
        logger.info("Direct outbound adapter stopped")
    }

    public func connect() async throws {
        guard isRunning else {
            throw AdapterError.configurationError("Adapter not running")
        }

        logger.debug("Direct outbound adapter ready for connections")
    }

    public func connect(to destination: String, port: Int) async throws -> any Channel {
        guard isRunning else {
            throw AdapterError.configurationError("Adapter not running")
        }

        return try await directOutbound.connect(to: destination, port: port)
    }

    public func connectUDP(to destination: String, port: Int) async throws -> any Channel {
        guard isRunning else {
            throw AdapterError.configurationError("Adapter not running")
        }

        return try await directOutbound.connectUDP(to: destination, port: port)
    }
}
