import Foundation
import Network

final class InboundEndpoint: @unchecked Sendable {
    typealias Handler = @Sendable (NWConnection, PipelineConfiguration) -> Void

    private let configuration: InboundEndpointConfiguration
    private let handler: Handler
    private let logger: Logging
    private let listener: NWListener
    private let port: NWEndpoint.Port

    init(configuration: InboundEndpointConfiguration, logger: Logging, handler: @escaping Handler) throws {
        precondition(!configuration.tag.isEmpty, "tag must not be empty")
        self.configuration = configuration
        self.handler = handler
        self.logger = logger
        (self.listener, self.port) = try InboundEndpoint.makeListener(bind: configuration.bind)

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            self.handler(connection, self.configuration.pipeline)
        }

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed(let error):
                self.logger.log(.error, "inbound \(self.configuration.tag) failed \(error.localizedDescription)")
            case .ready:
                self.logger.log(.info, "inbound \(self.configuration.tag) ready on \(self.configuration.bind.host):\(self.port.rawValue)")
            default:
                break
            }
        }
    }

    func start() {
        listener.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener.cancel()
    }

    private static func makeListener(bind: EndpointBind) throws -> (NWListener, NWEndpoint.Port) {
        guard let port = NWEndpoint.Port(rawValue: bind.port) else {
            throw Error.invalidConfiguration("port \(bind.port)")
        }

        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.noDelay = true

        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters, on: port)
        return (listener, port)
    }
}
