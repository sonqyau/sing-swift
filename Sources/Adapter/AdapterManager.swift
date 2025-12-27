import Foundation
import Logging
import NIO

public actor AdapterManager {
    private var inboundAdapters: [String: any InboundNetworkAdapter] = [:]
    private var outboundAdapters: [String: any OutboundNetworkAdapter] = [:]
    private let logger: Logger
    private let eventLoopGroup: any EventLoopGroup

    public init(eventLoopGroup: any EventLoopGroup, logger: Logger = Logger(label: "adapter-manager")) {
        self.eventLoopGroup = eventLoopGroup
        self.logger = logger
    }

    public func createInboundAdapter(
        configuration: InboundConfiguration,
    ) async throws -> any InboundNetworkAdapter {
        logger.info("Creating inbound adapter: \(configuration.tag) (\(configuration.protocolType))")

        let adapter: any InboundNetworkAdapter

        switch configuration.protocolType.lowercased() {
        case "http":
            adapter = await HttpInboundAdapter(
                tag: configuration.tag,
                configuration: configuration,
                eventLoopGroup: eventLoopGroup,
                logger: logger,
            )
        case "socks", "socks5":
            adapter = await SocksInboundAdapter(
                tag: configuration.tag,
                configuration: configuration,
                eventLoopGroup: eventLoopGroup,
                logger: logger,
            )
        case "mixed":
            adapter = await MixedInboundAdapter(
                tag: configuration.tag,
                configuration: configuration,
                eventLoopGroup: eventLoopGroup,
                logger: logger,
            )
        default:
            throw AdapterError.unsupportedProtocol(configuration.protocolType)
        }

        inboundAdapters[configuration.tag] = adapter
        return adapter
    }

    public func getInboundAdapter(tag: String) -> (any InboundNetworkAdapter)? {
        inboundAdapters[tag]
    }

    public func removeInboundAdapter(tag: String) async throws {
        if let adapter = inboundAdapters.removeValue(forKey: tag) {
            try await adapter.stop()
        }
    }

    public func createOutboundAdapter(
        configuration: OutboundConfiguration,
    ) async throws -> any OutboundNetworkAdapter {
        logger.info("Creating outbound adapter: \(configuration.tag) (\(configuration.protocolType))")

        let adapter: any OutboundNetworkAdapter

        switch configuration.protocolType.lowercased() {
        case "direct":
            adapter = await DirectOutboundAdapter(
                tag: configuration.tag,
                configuration: configuration,
                eventLoopGroup: eventLoopGroup,
                logger: logger,
            )
        case "block":
            adapter = await BlockOutboundAdapter(
                tag: configuration.tag,
                configuration: configuration,
                logger: logger,
            )
        default:
            throw AdapterError.unsupportedProtocol(configuration.protocolType)
        }

        outboundAdapters[configuration.tag] = adapter
        return adapter
    }

    public func getOutboundAdapter(tag: String) -> (any OutboundNetworkAdapter)? {
        outboundAdapters[tag]
    }

    public func removeOutboundAdapter(tag: String) async throws {
        if let adapter = outboundAdapters.removeValue(forKey: tag) {
            try await adapter.stop()
        }
    }

    public func startAll() async throws {
        logger.info("Starting all adapters")

        for (tag, adapter) in outboundAdapters {
            do {
                try await adapter.start()
                logger.info("Started outbound adapter: \(tag)")
            } catch {
                logger.error("Failed to start outbound adapter \(tag): \(error)")
                throw error
            }
        }

        for (tag, adapter) in inboundAdapters {
            do {
                try await adapter.start()
                logger.info("Started inbound adapter: \(tag)")
            } catch {
                logger.error("Failed to start inbound adapter \(tag): \(error)")
                throw error
            }
        }
    }

    public func stopAll() async throws {
        logger.info("Stopping all adapters")

        for (tag, adapter) in inboundAdapters {
            do {
                try await adapter.stop()
                logger.info("Stopped inbound adapter: \(tag)")
            } catch {
                logger.error("Failed to stop inbound adapter \(tag): \(error)")
            }
        }

        for (tag, adapter) in outboundAdapters {
            do {
                try await adapter.stop()
                logger.info("Stopped outbound adapter: \(tag)")
            } catch {
                logger.error("Failed to stop outbound adapter \(tag): \(error)")
            }
        }

        inboundAdapters.removeAll()
        outboundAdapters.removeAll()
    }
}

public enum AdapterError: Error, LocalizedError {
    case unsupportedProtocol(String)
    case adapterNotFound(String)
    case configurationError(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedProtocol(type):
            "Unsupported protocol: \(type)"
        case let .adapterNotFound(tag):
            "Adapter not found: \(tag)"
        case let .configurationError(message):
            "Configuration error: \(message)"
        }
    }
}
