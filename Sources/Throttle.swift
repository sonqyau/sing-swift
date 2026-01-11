import Darwin
import Foundation
import os.lock

final class Throttle: @unchecked Sendable {
    private let readRate: Int
    private let writeRate: Int
    private var readDeadline: DispatchTime
    private var writeDeadline: DispatchTime
    private var readLock: os_unfair_lock = .init()
    private var writeLock: os_unfair_lock = .init()

    init(configuration: ThrottleConfiguration) {
        precondition(configuration.readBytesPerSecond >= 0, "readBytesPerSecond must be non-negative")
        precondition(configuration.writeBytesPerSecond >= 0, "writeBytesPerSecond must be non-negative")

        self.readRate = configuration.readBytesPerSecond
        self.writeRate = configuration.writeBytesPerSecond
        self.readDeadline = DispatchTime.now()
        self.writeDeadline = DispatchTime.now()
    }

    func applyRead(bytes: Int) {
        guard readRate > 0, bytes > 0 else { return }
        delay(bytes: bytes, rate: readRate, lock: &readLock, deadline: &readDeadline)
    }

    func applyWrite(bytes: Int) {
        guard writeRate > 0, bytes > 0 else { return }
        delay(bytes: bytes, rate: writeRate, lock: &writeLock, deadline: &writeDeadline)
    }

    private func delay(bytes: Int, rate: Int, lock: inout os_unfair_lock, deadline: inout DispatchTime) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let now = DispatchTime.now()
        let base = deadline > now ? deadline : now
        let nanoseconds = UInt64(Double(bytes) / Double(rate) * 1_000_000_000)
        let clamped = min(nanoseconds, UInt64(Int.max))
        let target = base + .nanoseconds(Int(clamped))
        deadline = target

        let remaining =
            target.uptimeNanoseconds > now.uptimeNanoseconds
            ? target.uptimeNanoseconds - now.uptimeNanoseconds
            : 0

        if remaining > 0 {
            let microseconds = UInt64(min(remaining / 1000, UInt64(useconds_t.max)))
            if microseconds > 0 {
                usleep(useconds_t(microseconds))
            }
        }
    }
}
