import Foundation

public enum Error: Swift.Error, Sendable, LocalizedError {
    case alreadyRunning
    case notRunning
    case invalidConfiguration(String)
    case dnsFailure(String)
    case listenerFailure(String)
    case routeMissing(String)
    case outboundMissing(String)
    case connectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Kernel is already running"
        case .notRunning:
            return "Kernel is not running"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .dnsFailure(let host):
            return "DNS resolution failed for host: \(host)"
        case .listenerFailure(let message):
            return "Listener failed: \(message)"
        case .routeMissing(let key):
            return "Route missing for key: \(key)"
        case .outboundMissing(let tag):
            return "Outbound endpoint missing for tag: \(tag)"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        }
    }
}
