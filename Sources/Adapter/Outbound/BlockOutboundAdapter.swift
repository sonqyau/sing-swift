import Foundation
import Logging
import NIO

@MainActor
public final class BlockOutboundAdapter: OutboundNetworkAdapter {
    public let tag: String
    private let configuration: OutboundConfiguration
    private let logger: Logger
    private var isRunning = false

    public init(
        tag: String,
        configuration: OutboundConfiguration,
        logger: Logger,
    ) {
        self.tag = tag
        self.configuration = configuration
        self.logger = logger
    }

    public func start() async throws {
        guard !isRunning else {
            throw AdapterError.configurationError("Adapter already running")
        }

        logger.info("Starting Block outbound adapter")
        isRunning = true
        logger.info("Block outbound adapter started")
    }

    public func stop() async throws {
        guard isRunning else { return }

        logger.info("Stopping Block outbound adapter")
        isRunning = false
        logger.info("Block outbound adapter stopped")
    }

    public func connect() async throws {
        guard isRunning else {
            throw AdapterError.configurationError("Adapter not running")
        }

        logger.debug("Block outbound adapter ready (will block all connections)")
    }

    public func connect(to destination: String, port: Int) async throws -> any Channel {
        logger.info("Blocking connection to \(destination):\(port)")
        throw BlockError.connectionBlocked(destination: destination, port: port)
    }

    public func connectUDP(to destination: String, port: Int) async throws -> any Channel {
        logger.info("Blocking UDP connection to \(destination):\(port)")
        throw BlockError.connectionBlocked(destination: destination, port: port)
    }
}

public enum BlockError: Error, LocalizedError {
    case connectionBlocked(destination: String, port: Int)

    public var errorDescription: String? {
        switch self {
        case let .connectionBlocked(destination, port):
            "Connection blocked to \(destination):\(port)"
        }
    }
}
