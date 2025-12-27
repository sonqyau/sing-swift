import Foundation
import Logging
import NIO
import NIOHTTP1

private final class SendableByteToMessageHandler<Decoder: ByteToMessageDecoder>: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = Decoder.InboundOut
    typealias OutboundOut = Decoder.InboundOut

    private let wrapped: ByteToMessageHandler<Decoder>

    init(_ decoder: Decoder) {
        self.wrapped = ByteToMessageHandler(decoder)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        wrapped.channelRead(context: context, data: data)
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        wrapped.channelReadComplete(context: context)
    }

    func handlerAdded(context: ChannelHandlerContext) {
        wrapped.handlerAdded(context: context)
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        wrapped.handlerRemoved(context: context)
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        wrapped.errorCaught(context: context, error: error)
    }
}

private final class SendableHTTPResponseEncoder: ChannelOutboundHandler, @unchecked Sendable {
    typealias OutboundIn = HTTPServerResponsePart
    typealias OutboundOut = ByteBuffer

    private let wrapped = HTTPResponseEncoder()

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        wrapped.write(context: context, data: data, promise: promise)
    }

    func flush(context: ChannelHandlerContext) {
        wrapped.flush(context: context)
    }

    func handlerAdded(context: ChannelHandlerContext) {
        wrapped.handlerAdded(context: context)
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        wrapped.handlerRemoved(context: context)
    }
}

public struct HttpInbound: Inbound, @unchecked Sendable {
    private let logger: Logger

    public init(logger: Logger = Logger(label: "http-inbound")) {
        self.logger = logger
    }

    public func handle(context _: ChannelHandlerContext, connection: any Channel) async throws {
        let handler = HttpProxyChannelHandler(logger: logger)
        let decoder = SendableByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes))
        let encoder = SendableHTTPResponseEncoder()
        try await connection.pipeline.addHandler(decoder)
        try await connection.pipeline.addHandler(encoder)
        try await connection.pipeline.addHandler(handler)
    }
}

private final class HttpProxyChannelHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let logger: Logger
    private var state: ProxyState = .waitingForRequest

    private enum ProxyState {
        case waitingForRequest
        case connecting
        case connected
        case error
    }

    init(logger: Logger) {
        self.logger = logger
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let requestPart = unwrapInboundIn(data)

        switch requestPart {
        case let .head(head):
            handleRequestHead(context: context, head: head)
        case let .body(body):
            handleRequestBody(context: context, body: body)
        case .end:
            handleRequestEnd(context: context)
        }
    }

    private func handleRequestHead(context: ChannelHandlerContext, head: HTTPRequestHead) {
        logger.info("HTTP proxy request: \(head.method) \(head.uri)")

        if head.method == .CONNECT {
            handleConnectMethod(context: context, uri: head.uri)
        } else {
            handleHttpMethod(context: context, head: head)
        }
    }

    private func handleConnectMethod(context: ChannelHandlerContext, uri: String) {
        let components = uri.split(separator: ":")
        guard components.count == 2,
              let host = components.first,
              let port = Int(components.last ?? "")
        else {
            logger.warning("Invalid CONNECT request: \(uri)")
            sendErrorResponse(context: context, status: .badRequest)
            return
        }

        logger.info("CONNECT request to \(host):\(port)")

        let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: HTTPHeaders([
            ("Connection", "close"),
        ]))
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)

        state = .connected

        logger.debug("Establishing connection to target and starting tunneling")
    }

    private func handleHttpMethod(context: ChannelHandlerContext, head: HTTPRequestHead) {
        guard let url = URL(string: head.uri),
              let host = url.host
        else {
            logger.warning("Invalid HTTP proxy request: \(head.uri)")
            sendErrorResponse(context: context, status: .badRequest)
            return
        }

        let port = url.port ?? (url.scheme == "https" ? 443 : 80)

        logger.info("HTTP proxy request to \(host):\(port)")

        logger.debug("Forwarding request to target server")
        sendErrorResponse(context: context, status: .notImplemented)
    }

    private func handleRequestBody(context _: ChannelHandlerContext, body: ByteBuffer) {
        if state == .connected {
            logger.debug("Forwarding \(body.readableBytes) bytes to target")
        }
    }

    private func handleRequestEnd(context _: ChannelHandlerContext) {
        if state == .connected {
            logger.debug("HTTP request complete, continuing tunnel")
        }
    }

    private func sendErrorResponse(context: ChannelHandlerContext, status: HTTPResponseStatus) {
        let head = HTTPResponseHead(version: .http1_1, status: status, headers: HTTPHeaders([
            ("Connection", "close"),
            ("Content-Length", "0"),
        ]))
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        state = .error
        context.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        logger.error("HTTP proxy handler error: \(error)")
        context.close(promise: nil)
    }
}
