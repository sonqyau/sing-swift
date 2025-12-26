import Foundation
import NIO
import NIOHTTP1

public struct HttpInbound: InboundHandler {
    public init() {}

    public func handle(context: ChannelHandlerContext, connection: any Channel) async throws {
        _ = try await connection.pipeline.addHandler(HttpChannelHandler())
    }
}

private final class HttpChannelHandler: ChannelInboundHandler, Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.close(promise: nil)
    }
}
