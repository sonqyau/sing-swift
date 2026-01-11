import Foundation
import OSLog

public struct Logging: Sendable {
    private let logger: Logger

    public init(identity: KernelIdentity) {
        self.logger = Logger(subsystem: identity.subsystem, category: identity.category)
    }

    public func log(_ level: LogLevel, _ message: String) {
        switch level {
        case .trace, .debug:
            logger.log(level: .debug, "\(message, privacy: .public)")
        case .info, .notice:
            logger.log(level: .info, "\(message, privacy: .public)")
        case .warn:
            logger.log(level: .default, "\(message, privacy: .public)")
        case .error:
            logger.log(level: .error, "\(message, privacy: .public)")
        case .fault:
            logger.log(level: .fault, "\(message, privacy: .public)")
        }
    }
}
