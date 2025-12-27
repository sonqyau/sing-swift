import Foundation
import SystemPackage

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
        outboundTag: String,
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

        if let domains, domains.contains(destination) {
            return true
        }

        if let suffixes = domainSuffixes {
            for suffix in suffixes where destination.hasSuffix(suffix) {
                return true
            }
        }

        if let cidrBlocks = ipCIDRBlocks {
            for cidrBlock in cidrBlocks where await matchesCIDR(destination: destination, cidr: cidrBlock) {
                return true
            }
        }

        return false
    }

    private func matchesCIDR(destination: String, cidr: String) async -> Bool {
        let components = cidr.split(separator: "/")
        guard components.count == 2,
              let networkAddress = components.first,
              let prefixLength = Int(components.last ?? "")
        else {
            return false
        }

        if let destIPv4 = parseIPv4(String(destination)),
           let networkIPv4 = parseIPv4(String(networkAddress))
        {
            return matchesIPv4CIDR(ip: destIPv4, network: networkIPv4, prefixLength: prefixLength)
        }

        if let destIPv6 = parseIPv6(String(destination)),
           let networkIPv6 = parseIPv6(String(networkAddress))
        {
            return matchesIPv6CIDR(ip: destIPv6, network: networkIPv6, prefixLength: prefixLength)
        }

        return false
    }

    private func parseIPv4(_ ip: String) -> UInt32? {
        let components = ip.split(separator: ".")
        guard components.count == 4 else { return nil }

        var result: UInt32 = 0
        for (index, component) in components.enumerated() {
            guard let octet = UInt8(component) else { return nil }
            result |= UInt32(octet) << (8 * (3 - index))
        }
        return result
    }

    private func parseIPv6(_ ip: String) -> (UInt64, UInt64)? {
        let parts = ip.split(separator: ":")
        guard parts.count <= 8 else { return nil }

        var high: UInt64 = 0
        var low: UInt64 = 0

        for (index, part) in parts.enumerated() {
            guard let value = UInt16(part, radix: 16) else { return nil }
            if index < 4 {
                high |= UInt64(value) << (16 * (3 - index))
            } else {
                low |= UInt64(value) << (16 * (7 - index))
            }
        }

        return (high, low)
    }

    private func matchesIPv4CIDR(ip: UInt32, network: UInt32, prefixLength: Int) -> Bool {
        guard prefixLength >= 0, prefixLength <= 32 else { return false }

        if prefixLength == 0 {
            return true
        }

        let mask: UInt32 = ~((1 << (32 - prefixLength)) - 1)
        return (ip & mask) == (network & mask)
    }

    private func matchesIPv6CIDR(ip: (UInt64, UInt64), network: (UInt64, UInt64), prefixLength: Int) -> Bool {
        guard prefixLength >= 0, prefixLength <= 128 else { return false }

        if prefixLength == 0 {
            return true
        }

        if prefixLength <= 64 {
            let mask: UInt64 = ~((1 << (64 - prefixLength)) - 1)
            return (ip.0 & mask) == (network.0 & mask)
        } else {
            if ip.0 != network.0 {
                return false
            }
            let lowPrefixLength = prefixLength - 64
            let mask: UInt64 = ~((1 << (64 - lowPrefixLength)) - 1)
            return (ip.1 & mask) == (network.1 & mask)
        }
    }
}
