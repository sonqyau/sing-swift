import Foundation
import NIO
import NIOCore
import NIOTransportServices

public struct DirectOutbound: Outbound {
    public init() {}

    public func connect(to destination: String, port: Int) async throws -> any Channel {
        let eventLoopGroup = NIOTSEventLoopGroup()
        let bootstrap = ClientBootstrap(group: eventLoopGroup)
        return try await bootstrap.connect(host: destination, port: port).get()
    }
}
