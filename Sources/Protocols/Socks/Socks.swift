import Foundation
import Logging
import NIO
import NIOCore
import NIOSOCKS

public struct SocksInbound: Inbound {
    private let logger: Logger

    public init(logger: Logger = Logger(label: "socks-inbound")) {
        self.logger = logger
    }

    public func handle(context _: ChannelHandlerContext, connection: any Channel) async throws {
        let handler = SocksChannelHandler(logger: logger)
        _ = try await connection.pipeline.addHandler(handler)
    }
}

private final class SocksChannelHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let logger: Logger
    private var state: SocksState = .waitingForGreeting

    private enum SocksState {
        case waitingForGreeting
        case waitingForAuth
        case waitingForRequest
        case connected
        case error
    }

    init(logger: Logger) {
        self.logger = logger
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)

        switch state {
        case .waitingForGreeting:
            handleGreeting(context: context, buffer: buffer)
        case .waitingForAuth:
            handleAuth(context: context, buffer: buffer)
        case .waitingForRequest:
            handleRequest(context: context, buffer: buffer)
        case .connected:
            forwardData(context: context, buffer: buffer)
        case .error:
            context.close(promise: nil)
        }
    }

    private func handleGreeting(context: ChannelHandlerContext, buffer: ByteBuffer) {
        guard buffer.readableBytes >= 2 else {
            logger.warning("Invalid SOCKS5 greeting: insufficient data")
            state = .error
            context.close(promise: nil)
            return
        }

        var buffer = buffer
        guard let version = buffer.readInteger(as: UInt8.self),
              let methodCount = buffer.readInteger(as: UInt8.self)
        else {
            state = .error
            context.close(promise: nil)
            return
        }

        guard version == 5 else {
            logger.warning("Unsupported SOCKS version: \(version)")
            state = .error
            context.close(promise: nil)
            return
        }

        guard buffer.readableBytes >= methodCount else {
            logger.warning("Invalid SOCKS5 greeting: insufficient method data")
            state = .error
            context.close(promise: nil)
            return
        }

        var methods: [UInt8] = []
        for _ in 0 ..< methodCount {
            if let method = buffer.readInteger(as: UInt8.self) {
                methods.append(method)
            }
        }

        var response = context.channel.allocator.buffer(capacity: 2)
        response.writeInteger(UInt8(5))
        response.writeInteger(UInt8(0))

        context.writeAndFlush(wrapOutboundOut(response), promise: nil)
        state = .waitingForRequest
    }

    private func handleAuth(context _: ChannelHandlerContext, buffer _: ByteBuffer) {
        state = .waitingForRequest
    }

    private func handleRequest(context: ChannelHandlerContext, buffer: ByteBuffer) {
        guard buffer.readableBytes >= 4 else {
            logger.warning("Invalid SOCKS5 request: insufficient data")
            sendErrorResponse(context: context, errorCode: 1)
            return
        }

        var buffer = buffer
        guard let version = buffer.readInteger(as: UInt8.self),
              let command = buffer.readInteger(as: UInt8.self),
              buffer.readInteger(as: UInt8.self) != nil,
              let addressType = buffer.readInteger(as: UInt8.self)
        else {
            sendErrorResponse(context: context, errorCode: 1)
            return
        }

        guard version == 5 else {
            logger.warning("Invalid SOCKS version in request: \(version)")
            sendErrorResponse(context: context, errorCode: 1)
            return
        }

        guard command == 1 else {
            logger.warning("Unsupported SOCKS command: \(command)")
            sendErrorResponse(context: context, errorCode: 7)
            return
        }

        let address: String
        switch addressType {
        case 1: // IPv4
            guard buffer.readableBytes >= 6 else {
                sendErrorResponse(context: context, errorCode: 1)
                return
            }
            guard let ip1 = buffer.readInteger(as: UInt8.self),
                  let ip2 = buffer.readInteger(as: UInt8.self),
                  let ip3 = buffer.readInteger(as: UInt8.self),
                  let ip4 = buffer.readInteger(as: UInt8.self)
            else {
                sendErrorResponse(context: context, errorCode: 1)
                return
            }
            address = "\(ip1).\(ip2).\(ip3).\(ip4)"

        case 3: // Domain name
            guard let domainLength = buffer.readInteger(as: UInt8.self),
                  buffer.readableBytes >= Int(domainLength) + 2
            else {
                sendErrorResponse(context: context, errorCode: 1)
                return
            }
            guard let domainData = buffer.readBytes(length: Int(domainLength)),
                  let domain = String(bytes: domainData, encoding: .utf8)
            else {
                sendErrorResponse(context: context, errorCode: 1)
                return
            }
            address = domain

        case 4: // IPv6
            guard buffer.readableBytes >= 18 else {
                sendErrorResponse(context: context, errorCode: 1)
                return
            }
            var ipv6Parts: [String] = []
            for _ in 0 ..< 8 {
                guard let part = buffer.readInteger(as: UInt16.self) else {
                    sendErrorResponse(context: context, errorCode: 1)
                    return
                }
                ipv6Parts.append(String(format: "%04x", part))
            }
            address = ipv6Parts.joined(separator: ":")

        default:
            logger.warning("Unsupported address type: \(addressType)")
            sendErrorResponse(context: context, errorCode: 8)
            return
        }

        guard let port = buffer.readInteger(as: UInt16.self) else {
            sendErrorResponse(context: context, errorCode: 1)
            return
        }

        logger.info("SOCKS5 connection request to \(address):\(port)")

        sendSuccessResponse(context: context)
        state = .connected
    }

    private func sendErrorResponse(context: ChannelHandlerContext, errorCode: UInt8) {
        var response = context.channel.allocator.buffer(capacity: 10)
        response.writeInteger(UInt8(5)) // Version
        response.writeInteger(errorCode) // Error code
        response.writeInteger(UInt8(0)) // Reserved
        response.writeInteger(UInt8(1)) // IPv4 address type
        response.writeInteger(UInt32(0)) // Address (0.0.0.0)
        response.writeInteger(UInt16(0)) // Port

        context.writeAndFlush(wrapOutboundOut(response), promise: nil)
        state = .error
        context.close(promise: nil)
    }

    private func sendSuccessResponse(context: ChannelHandlerContext) {
        var response = context.channel.allocator.buffer(capacity: 10)
        response.writeInteger(UInt8(5)) // Version
        response.writeInteger(UInt8(0)) // Success
        response.writeInteger(UInt8(0)) // Reserved
        response.writeInteger(UInt8(1)) // IPv4 address type
        response.writeInteger(UInt32(0)) // Bound address (0.0.0.0)
        response.writeInteger(UInt16(0)) // Bound port

        context.writeAndFlush(wrapOutboundOut(response), promise: nil)
    }

    private func forwardData(context: ChannelHandlerContext, buffer: ByteBuffer) {
        logger.debug("Forwarding \(buffer.readableBytes) bytes to target")
        context.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        logger.error("SOCKS handler error: \(error)")
        context.close(promise: nil)
    }
}
