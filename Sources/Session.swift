import Foundation
import Network

final class Session: @unchecked Sendable {
    let id = UUID()

    private let inbound: NWConnection
    private let outbound: NWConnection
    private let logger: Logging
    private let throttle: Throttle?
    private let completion: @Sendable (UUID) -> Void
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var finished = false

    init(
        inbound: NWConnection,
        outbound: NWConnection,
        logger: Logging,
        throttle: ThrottleConfiguration?,
        completion: @escaping @Sendable (UUID) -> Void
    ) {
        self.inbound = inbound
        self.outbound = outbound
        self.logger = logger
        self.completion = completion
        self.throttle = throttle.map { Throttle(configuration: $0) }
        self.queue = DispatchQueue(label: "sing-swift.session.\(id.uuidString)", qos: .userInitiated)
    }

    func start() {
        inbound.stateUpdateHandler = { [weak self] state in
            self?.handle(state: state, label: "inbound")
        }

        outbound.stateUpdateHandler = { [weak self] state in
            self?.handle(state: state, label: "outbound")
        }

        inbound.start(queue: queue)
        outbound.start(queue: queue)

        pump(source: inbound, destination: outbound)
        pump(source: outbound, destination: inbound)
    }

    func cancel() {
        finish()
    }

    private func pump(source: NWConnection, destination: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                self.logger.log(.error, "session \(self.id.uuidString) error \(error.localizedDescription)")
                self.finish()
                return
            }

            if let data, !data.isEmpty {
                self.throttle?.applyRead(bytes: data.count)

                destination.send(
                    content: data,
                    completion: .contentProcessed { [weak self] sendError in
                        guard let self else { return }

                        if let sendError {
                            self.logger.log(.error, "session \(self.id.uuidString) send error \(sendError.localizedDescription)")
                            self.finish()
                            return
                        }

                        self.throttle?.applyWrite(bytes: data.count)
                    })
            }

            if isComplete || data == nil {
                self.finish()
                return
            }

            self.pump(source: source, destination: destination)
        }
    }

    private func handle(state: NWConnection.State, label: String) {
        switch state {
        case .failed(let error):
            logger.log(.error, "session \(id.uuidString) \(label) failed \(error.localizedDescription)")
            finish()
        case .cancelled:
            finish()
        default:
            break
        }
    }

    private func finish() {
        lock.lock()
        defer { lock.unlock() }

        guard !finished else { return }
        finished = true

        inbound.cancel()
        outbound.cancel()
        completion(id)
    }
}
