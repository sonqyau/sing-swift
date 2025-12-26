import Foundation
import NIO

public protocol Outbound: Sendable {
    func connect(to destination: String, port: Int) async throws -> any Channel
}
