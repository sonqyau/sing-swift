import Configuration
import Foundation

public struct Configuration: Codable, Sendable {
    public let logging: LoggingConfiguration?
    public let dns: DNSConfiguration?
    public let inbounds: [InboundConfiguration]
    public let outbounds: [OutboundConfiguration]
    public let routing: RoutingConfiguration?

    public init(
        logging: LoggingConfiguration? = nil,
        dns: DNSConfiguration? = nil,
        inbounds: [InboundConfiguration] = [],
        outbounds: [OutboundConfiguration] = [],
        routing: RoutingConfiguration? = nil,
    ) {
        self.logging = logging
        self.dns = dns
        self.inbounds = inbounds
        self.outbounds = outbounds
        self.routing = routing
    }
}

public struct LoggingConfiguration: Codable, Sendable {
    public let level: String
    public let isDisabled: Bool

    public init(level: String = "info", isDisabled: Bool = false) {
        self.level = level
        self.isDisabled = isDisabled
    }
}

public struct DNSConfiguration: Codable, Sendable {
    public let servers: [DNSServerConfiguration]
    public let rules: [DNSRuleConfiguration]?
    public let resolutionStrategy: String
    public let isCacheDisabled: Bool

    public init(
        servers: [DNSServerConfiguration],
        rules: [DNSRuleConfiguration]? = nil,
        resolutionStrategy: String = "preferIPv4",
        isCacheDisabled: Bool = false,
    ) {
        self.servers = servers
        self.rules = rules
        self.resolutionStrategy = resolutionStrategy
        self.isCacheDisabled = isCacheDisabled
    }
}

public struct DNSServerConfiguration: Codable, Sendable {
    public let address: String
    public let port: Int?
    public let resolutionStrategy: String?

    public init(address: String, port: Int? = nil, resolutionStrategy: String? = nil) {
        self.address = address
        self.port = port
        self.resolutionStrategy = resolutionStrategy
    }
}

public struct DNSRuleConfiguration: Codable, Sendable {
    public let domains: [String]?
    public let domainSuffixes: [String]?
    public let serverAddress: String

    public init(domains: [String]? = nil, domainSuffixes: [String]? = nil, serverAddress: String) {
        self.domains = domains
        self.domainSuffixes = domainSuffixes
        self.serverAddress = serverAddress
    }
}

public struct InboundConfiguration: Codable, Sendable {
    public let protocolType: String
    public let tag: String
    public let listenAddress: String
    public let port: Int

    public init(protocolType: String, tag: String, listenAddress: String = "127.0.0.1", port: Int) {
        self.protocolType = protocolType
        self.tag = tag
        self.listenAddress = listenAddress
        self.port = port
    }
}

public struct OutboundConfiguration: Codable, Sendable {
    public let protocolType: String
    public let tag: String
    public let serverAddress: String?
    public let serverPort: Int?

    public init(protocolType: String, tag: String, serverAddress: String? = nil, serverPort: Int? = nil) {
        self.protocolType = protocolType
        self.tag = tag
        self.serverAddress = serverAddress
        self.serverPort = serverPort
    }
}

public struct RoutingConfiguration: Codable, Sendable {
    public let rules: [RoutingRuleConfiguration]
    public let defaultOutbound: String

    public init(rules: [RoutingRuleConfiguration] = [], defaultOutbound: String = "direct") {
        self.rules = rules
        self.defaultOutbound = defaultOutbound
    }
}

public struct RoutingRuleConfiguration: Codable, Sendable {
    public let domains: [String]?
    public let domainSuffixes: [String]?
    public let ipCIDRBlocks: [String]?
    public let ports: [Int]?
    public let outboundTag: String

    public init(
        domains: [String]? = nil,
        domainSuffixes: [String]? = nil,
        ipCIDRBlocks: [String]? = nil,
        ports: [Int]? = nil,
        outboundTag: String,
    ) {
        self.domains = domains
        self.domainSuffixes = domainSuffixes
        self.ipCIDRBlocks = ipCIDRBlocks
        self.ports = ports
        self.outboundTag = outboundTag
    }
}

public extension Configuration {
    static func loadFromJSON(at url: URL) throws -> Configuration {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Configuration.self, from: data)
    }

    func saveToJSON(at url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(self)
        try data.write(to: url)
    }

    static func `default`() -> Configuration {
        Configuration(
            logging: LoggingConfiguration(level: "info"),
            dns: DNSConfiguration(
                servers: [
                    DNSServerConfiguration(address: "8.8.8.8"),
                    DNSServerConfiguration(address: "1.1.1.1"),
                ],
            ),
            inbounds: [
                InboundConfiguration(protocolType: "mixed", tag: "mixed-in", port: 7890),
            ],
            outbounds: [
                OutboundConfiguration(protocolType: "direct", tag: "direct"),
            ],
            routing: RoutingConfiguration(defaultOutbound: "direct"),
        )
    }
}
