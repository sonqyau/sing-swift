import _Concurrency
import AsyncDNSResolver
import Foundation
import Logging

public actor DNSResolver {
    private let logger: Logger
    private let configuration: DNSConfiguration?

    public init(configuration: DNSConfiguration? = nil, logger: Logger = Logger(label: "dns-resolver")) {
        self.configuration = configuration
        self.logger = logger

        logger.info("DNS resolver initialized")
    }

    public func resolve(hostname: String) async throws -> [String] {
        logger.debug("Resolving hostname: \(hostname)")

        let result: [String] = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], any Error>) in
            Task {
                do {
                    let host = CFHostCreateWithName(nil, hostname as CFString).takeRetainedValue()
                    var resolved: DarwinBoolean = false

                    if CFHostStartInfoResolution(host, .addresses, nil) {
                        let addresses = CFHostGetAddressing(host, &resolved)

                        if resolved.boolValue, let addressArray = addresses?.takeUnretainedValue() {
                            var resolvedAddresses: [String] = []

                            for i in 0 ..< CFArrayGetCount(addressArray) {
                                let addressData = CFArrayGetValueAtIndex(addressArray, i)
                                let data = Unmanaged<CFData>.fromOpaque(addressData ?? UnsafeRawPointer(bitPattern: 0)!).takeUnretainedValue()
                                let sockaddr = CFDataGetBytePtr(data).withMemoryRebound(to: sockaddr.self, capacity: 1) { $0.pointee }

                                if sockaddr.sa_family == AF_INET {
                                    let addr = withUnsafePointer(to: sockaddr) {
                                        $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                                    }
                                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                                    _ = withUnsafePointer(to: addr.sin_addr) { addrPtr in
                                        inet_ntop(AF_INET, addrPtr, &buffer, socklen_t(INET_ADDRSTRLEN))
                                    }
                                    let addressString = String(bytes: buffer, encoding: .utf8) ?? ""
                                    resolvedAddresses.append(addressString)
                                }
                            }

                            continuation.resume(returning: resolvedAddresses)
                        } else {
                            continuation.resume(throwing: DNSError.resolutionFailed(hostname: hostname, error: NSError(domain: "DNSResolver", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to resolve hostname"])))
                        }
                    } else {
                        continuation.resume(throwing: DNSError.resolutionFailed(hostname: hostname, error: NSError(domain: "DNSResolver", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to start resolution"])))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        return result
    }

    public func resolveIPv4(hostname: String) async throws -> [String] {
        logger.debug("Resolving IPv4 for hostname: \(hostname)")

        let addresses = try await resolve(hostname: hostname)
        let ipv4Addresses = addresses.filter { isIPv4Address($0) }

        logger.debug("Resolved \(hostname) to \(ipv4Addresses.count) IPv4 addresses: \(ipv4Addresses)")
        return ipv4Addresses
    }

    public func resolveIPv6(hostname: String) async throws -> [String] {
        logger.debug("Resolving IPv6 for hostname: \(hostname)")

        let addresses = try await resolve(hostname: hostname)
        let ipv6Addresses = addresses.filter { isIPv6Address($0) }

        logger.debug("Resolved \(hostname) to \(ipv6Addresses.count) IPv6 addresses: \(ipv6Addresses)")
        return ipv6Addresses
    }

    private func isIPv4Address(_ address: String) -> Bool {
        let parts = address.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }

    private func isIPv6Address(_ address: String) -> Bool {
        address.contains(":")
    }

    public func isIPAddress(_ address: String) -> Bool {
        isIPv4Address(address) || isIPv6Address(address)
    }

    public func shouldResolve(destination: String) -> Bool {
        if isIPAddress(destination) {
            logger.debug("Destination \(destination) is already an IP address, skipping resolution")
            return false
        }

        if let dnsConfig = configuration,
           let rules = dnsConfig.rules
        {
            for rule in rules {
                if let domains = rule.domains, domains.contains(destination) {
                    logger.debug("Destination \(destination) matches DNS rule domain")
                    return true
                }

                if let suffixes = rule.domainSuffixes {
                    for suffix in suffixes where destination.hasSuffix(suffix) {
                        logger.debug("Destination \(destination) matches DNS rule suffix: \(suffix)")
                        return true
                    }
                }
            }
        }

        return true
    }
}

public enum DNSError: Error, LocalizedError {
    case resolutionFailed(hostname: String, error: any Error)
    case invalidConfiguration(String)

    public var errorDescription: String? {
        switch self {
        case let .resolutionFailed(hostname, error):
            "Failed to resolve hostname '\(hostname)': \(error.localizedDescription)"
        case let .invalidConfiguration(message):
            "Invalid DNS configuration: \(message)"
        }
    }
}
