import UIKit

@MainActor final class SyncBackgroundTask {
    private var identifier = UIBackgroundTaskIdentifier.invalid
    private let expired: () -> Void
    init(expired: @escaping () -> Void) { self.expired = expired }
    func begin() throws {
        precondition(identifier == .invalid)
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Collection sync") { [weak self] in
            Task { @MainActor in self?.expire() }
        }
        guard identifier != .invalid else {
            throw EngineError(message: "同期の実行時間を確保できませんでした。アプリを前面に戻してから再試行してください。")
        }
    }
    func end() {
        guard identifier != .invalid else { return }
        let ending = identifier
        identifier = .invalid
        UIApplication.shared.endBackgroundTask(ending)
    }
    private func expire() {
        guard identifier != .invalid else { return }
        expired()
        // Release the assertion promptly; persistent state covers a suspension
        // before the native cancellation has finished unwinding.
        end()
    }
    #if DEBUG
    func simulateExpiration() { expire() }
    #endif
}
