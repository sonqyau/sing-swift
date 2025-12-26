import Foundation
import NIO
import NIOTransportServices

public actor Kernel {
    private let eventLoopGroup: any EventLoopGroup
    private var isRunning = false
    private var startTime: Date?
    private var configuration: Configuration?
    private var channels: [any Channel] = []

    public init() {
        self.eventLoopGroup = NIOTSEventLoopGroup()
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

        self.configuration = configuration

        try await startInbounds(configuration.inbounds)

        isRunning = true
        startTime = Date()
    }

    public func stop() async throws {
        guard isRunning else {
            throw KernelError.notRunning
        }

        for channel in channels {
            try? await channel.close()
        }

        channels.removeAll()
        isRunning = false
        startTime = nil
        configuration = nil
    }

    public func status() -> KernelStatus {
        return KernelStatus(
            isRunning: isRunning,
            startTime: startTime,
            version: ApplicationVersion.current
        )
    }

    private func startInbounds(_ inbounds: [InboundConfiguration]) async throws {
        for inbound in inbounds {
            try await startInbound(inbound)
        }
    }

    private func startInbound(_ inbound: InboundConfiguration) async throws {
        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                return channel.eventLoop.makeSucceededVoidFuture()
            }

        let channel = try await bootstrap.bind(host: inbound.listenAddress, port: inbound.port).get()
        channels.append(channel)
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
            return "Kernel is already running"
        case .notRunning:
            return "Kernel is not running"
        case .unsupportedProtocol(let type):
            return "Unsupported protocol: \(type)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}
