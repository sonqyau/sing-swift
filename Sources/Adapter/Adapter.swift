import Foundation

public protocol NetworkAdapter: Sendable {
    var tag: String { get }

    func start() async throws

    func stop() async throws
}

public protocol InboundNetworkAdapter: NetworkAdapter {
    func serve() async throws
}

public protocol OutboundNetworkAdapter: NetworkAdapter {
    func connect() async throws
}
