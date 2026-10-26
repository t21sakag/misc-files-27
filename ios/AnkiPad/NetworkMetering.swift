import Foundation
import Network

/// Wait for the system's first path report rather than guessing the network cost.
final class NetworkMetering: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var expensive: Bool?
    private var waiters: [CheckedContinuation<Bool, Never>] = []
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.expensive = path.isExpensive
            let pending = self.waiters
            self.waiters = []
            self.lock.unlock()
            for waiter in pending { waiter.resume(returning: path.isExpensive) }
        }
        monitor.start(queue: DispatchQueue(label: "AnkiPad.network-cost", qos: .utility))
    }
    deinit { monitor.cancel() }
    func isMetered() async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let expensive {
                lock.unlock()
                continuation.resume(returning: expensive)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }
}
