import Foundation
import Logging
import NIO
import NIOCore
import NIOTransportServices

public struct DirectOutbound: Outbound {
    private let logger: Logger
    private let eventLoopGroup: any EventLoopGroup

    public init(eventLoopGroup: (any EventLoopGroup)? = nil, logger: Logger = Logger(label: "direct-outbound")) {
        self.logger = logger
        self.eventLoopGroup = eventLoopGroup ?? NIOTSEventLoopGroup()
    }

    public func connect(to destination: String, port: Int) async throws -> any Channel {
        logger.info("Connecting directly to \(destination):\(port)")

        let bootstrap = ClientBootstrap(group: eventLoopGroup)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.eventLoop.makeSucceededVoidFuture()
            }

        do {
            let channel = try await bootstrap.connect(host: destination, port: port).get()
            logger.info("Connected to \(destination):\(port)")
            return channel
        } catch {
            logger.error("Failed to connect to \(destination):\(port) - \(error)")
            throw error
        }
    }

    public func connectUDP(to destination: String, port: Int) async throws -> any Channel {
        logger.info("Creating UDP connection to \(destination):\(port)")

        let bootstrap = DatagramBootstrap(group: eventLoopGroup)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.eventLoop.makeSucceededVoidFuture()
            }

        do {
            let channel = try await bootstrap.connect(host: destination, port: port).get()
            logger.info("Created UDP connection to \(destination):\(port)")
            return channel
        } catch {
            logger.error("Failed to create UDP connection to \(destination):\(port) - \(error)")
            throw error
        }
    }
}
