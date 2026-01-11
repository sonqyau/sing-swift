import Foundation

public struct Configuration: Sendable, Codable {
    public var identity: KernelIdentity
    public var log: LogConfiguration
    public var dns: DNSConfiguration
    public var inbounds: [InboundEndpointConfiguration]
    public var outbounds: [OutboundEndpointConfiguration]
    public var routes: [RouteConfiguration]

    public init(
        identity: KernelIdentity,
        log: LogConfiguration,
        dns: DNSConfiguration,
        inbounds: [InboundEndpointConfiguration],
        outbounds: [OutboundEndpointConfiguration],
        routes: [RouteConfiguration]
    ) {
        self.identity = identity
        self.log = log
        self.dns = dns
        self.inbounds = inbounds
        self.outbounds = outbounds
        self.routes = routes
    }
}

public struct KernelIdentity: Sendable, Codable {
    public var subsystem: String
    public var category: String

    public init(subsystem: String, category: String) {
        precondition(!subsystem.isEmpty, "subsystem must not be empty")
        precondition(!category.isEmpty, "category must not be empty")
        self.subsystem = subsystem
        self.category = category
    }
}

public struct LogConfiguration: Sendable, Codable {
    public var level: LogLevel
    public var retention: TimeInterval

    public init(level: LogLevel, retention: TimeInterval) {
        precondition(retention >= 0, "retention must be non-negative")
        self.level = level
        self.retention = retention
    }
}

public enum LogLevel: String, Sendable, Codable {
    case trace
    case debug
    case info
    case notice
    case warn
    case error
    case fault
}

public struct DNSConfiguration: Sendable, Codable {
    public var servers: [String]
    public var searchDomains: [String]
    public var timeout: TimeInterval

    public init(servers: [String], searchDomains: [String], timeout: TimeInterval) {
        precondition(timeout > 0, "timeout must be positive")
        self.servers = servers
        self.searchDomains = searchDomains
        self.timeout = timeout
    }
}

public struct InboundEndpointConfiguration: Sendable, Codable {
    public var tag: String
    public var bind: EndpointBind
    public var pipeline: PipelineConfiguration

    public init(tag: String, bind: EndpointBind, pipeline: PipelineConfiguration) {
        precondition(!tag.isEmpty, "tag must not be empty")
        self.tag = tag
        self.bind = bind
        self.pipeline = pipeline
    }
}

public struct EndpointBind: Sendable, Codable {
    public var host: String
    public var port: UInt16

    public init(host: String, port: UInt16) {
        precondition(!host.isEmpty, "host must not be empty")
        precondition(port > 0, "port must be positive")
        self.host = host
        self.port = port
    }
}

public struct PipelineConfiguration: Sendable, Codable {
    public var routeKey: String?
    public var outboundTag: String?
    public var targetOverride: EndpointTarget?
    public var throttle: ThrottleConfiguration?

    public init(
        routeKey: String? = nil,
        outboundTag: String? = nil,
        targetOverride: EndpointTarget? = nil,
        throttle: ThrottleConfiguration? = nil
    ) {
        self.routeKey = routeKey
        self.outboundTag = outboundTag
        self.targetOverride = targetOverride
        self.throttle = throttle
    }
}

public struct ThrottleConfiguration: Sendable, Codable {
    public var readBytesPerSecond: Int
    public var writeBytesPerSecond: Int

    public init(readBytesPerSecond: Int, writeBytesPerSecond: Int) {
        precondition(readBytesPerSecond >= 0, "readBytesPerSecond must be non-negative")
        precondition(writeBytesPerSecond >= 0, "writeBytesPerSecond must be non-negative")
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
    }
}

public struct OutboundEndpointConfiguration: Sendable, Codable {
    public var tag: String
    public var target: EndpointTarget
    public var tls: TLSConfiguration?
    public var tcp: TCPConfiguration?

    public init(
        tag: String,
        target: EndpointTarget,
        tls: TLSConfiguration? = nil,
        tcp: TCPConfiguration? = nil
    ) {
        precondition(!tag.isEmpty, "tag must not be empty")
        self.tag = tag
        self.target = target
        self.tls = tls
        self.tcp = tcp
    }
}

public struct EndpointTarget: Sendable, Codable {
    public var host: String
    public var port: UInt16

    public init(host: String, port: UInt16) {
        precondition(!host.isEmpty, "host must not be empty")
        precondition(port > 0, "port must be positive")
        self.host = host
        self.port = port
    }
}

public struct TLSConfiguration: Sendable, Codable {
    public var enable: Bool
    public var hostnameOverride: String?

    public init(enable: Bool, hostnameOverride: String? = nil) {
        self.enable = enable
        self.hostnameOverride = hostnameOverride
    }
}

public struct TCPConfiguration: Sendable, Codable {
    public var disableHappyEyeballs: Bool
    public var keepAlive: Bool

    public init(disableHappyEyeballs: Bool, keepAlive: Bool) {
        self.disableHappyEyeballs = disableHappyEyeballs
        self.keepAlive = keepAlive
    }
}

public struct RouteConfiguration: Sendable, Codable {
    public var key: String
    public var outbound: String

    public init(key: String, outbound: String) {
        precondition(!key.isEmpty, "key must not be empty")
        precondition(!outbound.isEmpty, "outbound must not be empty")
        self.key = key
        self.outbound = outbound
    }
}
