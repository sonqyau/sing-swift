import _NIOConcurrency
import Foundation
import Logging
import NIO

public struct MixedInbound: Inbound {
    private let logger: Logger

    public init(logger: Logger = Logger(label: "mixed-inbound")) {
        self.logger = logger
    }

    public func handle(context _: ChannelHandlerContext, connection: any Channel) async throws {
        let handler = MixedProtocolHandler(logger: logger)
        _ = try await connection.pipeline.addHandler(handler)
    }
}

private final class MixedProtocolHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let logger: Logger
    private var detectedProtocol: DetectedProtocol?
    private var bufferedData: ByteBuffer?

    private enum DetectedProtocol {
        case http
        case socks5
    }

    init(logger: Logger) {
        self.logger = logger
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)

        if detectedProtocol == nil {
            if let detectedProto = detectProtocol(from: buffer) {
                detectedProtocol = detectedProto
                logger.info("Detected protocol: \(detectedProto)")

                switchToProtocolHandler(context: context, protocol: detectedProto, initialData: buffer)
            } else {
                if bufferedData == nil {
                    bufferedData = context.channel.allocator.buffer(capacity: buffer.readableBytes)
                }
                if var bufferedData {
                    bufferedData.writeImmutableBuffer(buffer)

                    if let detectedProto = detectProtocol(from: bufferedData) {
                        detectedProtocol = detectedProto
                        logger.info("Detected protocol: \(detectedProto) (buffered)")
                        switchToProtocolHandler(context: context, protocol: detectedProto, initialData: bufferedData)
                        self.bufferedData = nil
                    }
                }
            }
        } else {
            logger.warning("Received data after protocol detection")
            context.close(promise: nil)
        }
    }

    private func detectProtocol(from buffer: ByteBuffer) -> DetectedProtocol? {
        guard let firstByte = buffer.getBytes(at: buffer.readerIndex, length: 1)?.first else {
            return nil
        }

        if firstByte == 0x05 {
            return .socks5
        }

        if firstByte >= 0x41, firstByte <= 0x5A {
            if let methodBytes = buffer.getBytes(at: buffer.readerIndex, length: min(8, buffer.readableBytes)),
               let methodString = String(bytes: methodBytes, encoding: .ascii)
            {
                let httpMethods = ["GET ", "POST", "PUT ", "DELE", "HEAD", "OPTI", "CONN", "TRAC", "PATC"]
                for method in httpMethods where methodString.hasPrefix(method) {
                    return .http
                }
            }
        }

        return nil
    }

    private func switchToProtocolHandler(context: ChannelHandlerContext, protocol detectedProtocol: DetectedProtocol, initialData: ByteBuffer) {
        let removeFuture = context.pipeline.removeHandler(self)
        let channel = context.channel

        removeFuture.whenComplete { [weak self] (result: Result<Void, Error>) in
            switch result {
            case .success:
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        switch detectedProtocol {
                        case .http:
                            let httpInbound = HttpInbound(logger: self.logger)
                            try await httpInbound.handle(context: channel.pipeline.context, connection: channel)
                        case .socks5:
                            let socksInbound = SocksInbound(logger: self.logger)
                            try await socksInbound.handle(context: channel.pipeline.context, connection: channel)
                        }

                        channel.pipeline.fireChannelRead(NIOAny(initialData))
                    } catch {
                        self.logger.error("Failed to switch protocol handler: \(error)")
                        channel.close(promise: nil)
                    }
                }
            case let .failure(error):
                self?.logger.error("Failed to remove mixed protocol handler: \(error)")
                channel.close(promise: nil)
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        logger.error("Mixed protocol handler error: \(error)")
        context.close(promise: nil)
    }
}
