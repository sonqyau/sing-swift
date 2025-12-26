import Foundation
import NIO

public protocol InboundHandler: Sendable {
    func handle(context: ChannelHandlerContext, connection: any Channel) async throws
}
