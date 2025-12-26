import Foundation
import NIO

public struct SocksInbound: InboundHandler {
    public init() {}

    public func handle(context: ChannelHandlerContext, connection: any Channel) async throws {
        _ = try await connection.pipeline.addHandler(SocksChannelHandler())
    }
}

private final class SocksChannelHandler: ChannelInboundHandler, Sendable {
    typealias InboundIn = ByteBuffer

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        _ = unwrapInboundIn(data)
        context.close(promise: nil)
    }
}
