import Foundation
import NIO

public struct MixedInbound: InboundHandler {
    public init() {}

    public func handle(context: ChannelHandlerContext, connection: any Channel) async throws {
        _ = try await connection.pipeline.addHandler(MixedProtocolHandler())
    }
}

private final class MixedProtocolHandler: ChannelInboundHandler, Sendable {
    typealias InboundIn = ByteBuffer

    private enum DetectedProtocol: Sendable {
        case http
        case socks
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        _ = detectProtocol(from: buffer)
        context.close(promise: nil)
    }

    private func detectProtocol(from buffer: ByteBuffer) -> DetectedProtocol? {
        guard let firstByte = buffer.getBytes(at: buffer.readerIndex, length: 1)?.first else {
            return nil
        }

        if firstByte == 0x05 {
            return .socks
        }

        if firstByte >= 0x41 && firstByte <= 0x5A {
            return .http
        }

        return nil
    }
}
