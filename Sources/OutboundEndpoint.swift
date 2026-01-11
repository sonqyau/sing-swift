import Foundation
import Network
import Security

final class OutboundEndpoint: @unchecked Sendable {
    private let configuration: OutboundEndpointConfiguration

    init(configuration: OutboundEndpointConfiguration) throws {
        precondition(!configuration.tag.isEmpty, "tag must not be empty")
        self.configuration = configuration
        try OutboundEndpoint.validate(target: configuration.target)
    }

    func makeConnection(overrideTarget: EndpointTarget?, resolver: DNSResolver) throws -> NWConnection {
        let target = overrideTarget ?? configuration.target
        try resolver.validate(target: target)

        guard let port = NWEndpoint.Port(rawValue: target.port) else {
            throw Error.invalidConfiguration("port \(target.port)")
        }

        let parameters = makeParameters()
        parameters.allowFastOpen = true
        parameters.preferNoProxies = true

        let connection = NWConnection(host: NWEndpoint.Host(target.host), port: port, using: parameters)
        return connection
    }

    private static func validate(target: EndpointTarget) throws {
        guard !target.host.isEmpty else {
            throw Error.invalidConfiguration("missing host")
        }
        guard (1...UInt16.max).contains(target.port) else {
            throw Error.invalidConfiguration("port \(target.port)")
        }
    }

    private func makeParameters() -> NWParameters {
        let tls = OutboundEndpoint.makeTLSOptions(configuration: configuration)
        let tcp = OutboundEndpoint.makeTCPOptions(configuration.tcp)
        return NWParameters(tls: tls, tcp: tcp)
    }

    private static func makeTCPOptions(_ configuration: TCPConfiguration?) -> NWProtocolTCP.Options {
        let options = NWProtocolTCP.Options()

        if configuration?.disableHappyEyeballs == true {
            options.enableFastOpen = false
        } else {
            options.enableFastOpen = true
        }

        options.enableKeepalive = configuration?.keepAlive ?? true
        options.noDelay = true

        return options
    }

    private static func makeTLSOptions(configuration: OutboundEndpointConfiguration) -> NWProtocolTLS.Options? {
        guard configuration.tls?.enable == true else {
            return nil
        }

        let options = NWProtocolTLS.Options()
        let hostname = configuration.tls?.hostnameOverride ?? configuration.target.host

        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options.securityProtocolOptions, .TLSv13)

        hostname.withCString { name in
            sec_protocol_options_set_tls_server_name(options.securityProtocolOptions, name)
        }

        return options
    }
}
