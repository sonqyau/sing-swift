import Foundation

public enum Network: String, Codable, Sendable, CaseIterable {
    case tcp
    case udp
}

public enum Protocol: String, Codable, Sendable, CaseIterable {
    case http
    case socks
    case mixed
    case direct
    case block
    case vless
    case anyTLS = "anytls"
}

public enum Version {
    public static let current = "0.0.1"
    public static let name = "sing-swift"
    public static let displayName = "sing-swift"
}
