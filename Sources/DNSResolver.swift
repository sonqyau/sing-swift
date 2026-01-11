import CFNetwork
import Foundation

final class DNSResolver {
    private let configuration: DNSConfiguration
    private let logger: Logging

    init(configuration: DNSConfiguration, logger: Logging) {
        self.configuration = configuration
        self.logger = logger
    }

    func warmUp() throws {
        let hosts = configuration.servers + configuration.searchDomains
        for host in hosts where !host.isEmpty {
            _ = try resolve(host)
        }
    }

    func validate(target: EndpointTarget) throws {
        _ = try resolve(target.host)
    }

    private func resolve(_ host: String) throws -> [String] {
        if let literal = literalAddress(host) {
            return [literal]
        }

        let cfHost = CFHostCreateWithName(nil, host as CFString).takeRetainedValue()
        var streamError = CFStreamError()
        let result = CFHostStartInfoResolution(cfHost, .addresses, &streamError)

        guard result else {
            throw Error.dnsFailure(host)
        }

        var resolved: DarwinBoolean = false
        guard let values = CFHostGetAddressing(cfHost, &resolved)?.takeUnretainedValue() as? [Data],
            resolved.boolValue
        else {
            throw Error.dnsFailure(host)
        }

        let addresses = values.compactMap { data -> String? in
            data.withUnsafeBytes { pointer in
                guard let base = pointer.baseAddress else { return nil }
                let sockaddrPointer = base.assumingMemoryBound(to: sockaddr.self)
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let status = getnameinfo(
                    sockaddrPointer,
                    socklen_t(data.count),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )

                if status == 0 {
                    let bytes = hostname.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                    return String(decoding: bytes, as: UTF8.self)
                }
                return nil
            }
        }

        guard !addresses.isEmpty else {
            throw Error.dnsFailure(host)
        }

        logger.log(.debug, "resolved \(host) -> \(addresses.joined(separator: ","))")
        return addresses
    }

    private func literalAddress(_ host: String) -> String? {
        var ipv4 = in_addr()
        var ipv6 = in6_addr()

        if inet_pton(AF_INET, host, &ipv4) == 1 {
            return host
        }

        if inet_pton(AF_INET6, host, &ipv6) == 1 {
            return host
        }

        return nil
    }
}
