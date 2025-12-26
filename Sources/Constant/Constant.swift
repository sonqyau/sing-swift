import Foundation

public enum NetworkType: String, Codable, Sendable, CaseIterable {
    case tcp = "tcp"
    case udp = "udp"
}

public enum CommunicationProtocol: String, Codable, Sendable, CaseIterable {
    case http = "http"
    case socks = "socks"
    case mixed = "mixed"
    case direct = "direct"
    case block = "block"
    case vless = "vless"
    case anyTLS = "anytls"
}

public enum ApplicationVersion {
    public static let current = "0.0.1"
    public static let name = "sing-swift"
    public static let displayName = "sing-swift"
}
