import Foundation

public protocol Router: Sendable {
    func route(destination: String, port: Int) async -> String
}

public struct DefaultRouter: Router {
    private let rules: [RoutingRule]
    private let defaultOutbound: String

    public init(rules: [RoutingRule], defaultOutbound: String) {
        self.rules = rules
        self.defaultOutbound = defaultOutbound
    }

    public func route(destination: String, port: Int) async -> String {
        for rule in rules where await rule.matches(destination: destination, port: port) {
            return rule.outboundTag
        }
        return defaultOutbound
    }
}

public struct RoutingRule: Sendable {
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
        outboundTag: String
    ) {
        self.domains = domains
        self.domainSuffixes = domainSuffixes
        self.ipCIDRBlocks = ipCIDRBlocks
        self.ports = ports
        self.outboundTag = outboundTag
    }

    public func matches(destination: String, port: Int) async -> Bool {
        if let ports = self.ports, !ports.contains(port) {
            return false
        }

        if let domains = domains, domains.contains(destination) {
            return true
        }

        if let suffixes = domainSuffixes {
            for suffix in suffixes where destination.hasSuffix(suffix) {
                return true
            }
        }

        // TODO: Implement IP CIDR block matching

        return false
    }
}
