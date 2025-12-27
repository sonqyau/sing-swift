import Foundation
import NIO

public protocol Inbound: Sendable {
    func handle(context: ChannelHandlerContext, connection: any Channel) async throws
}
