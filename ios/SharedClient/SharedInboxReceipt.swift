import Foundation

@MainActor final class SharedInboxReceipt {
    let id: UUID
    private let inbox: SharedInbox
    private let resolved: (UUID, Bool) -> Void
    private var finished = false
    private var accepted = false
    private var acknowledgment: Task<Bool, Never>?
    init(id: UUID, inbox: SharedInbox, resolved: @escaping (UUID, Bool) -> Void) {
        self.id = id; self.inbox = inbox; self.resolved = resolved
    }
    func accept() async -> Bool {
        if finished { return accepted }
        let inbox = inbox, id = id
        let task = acknowledgment ?? Task.detached(priority: .utility) {
            do { try inbox.finish(id); return true }
            catch { return false }
        }
        acknowledgment = task
        let result = await task.value
        guard !finished else { return accepted }
        finished = true; accepted = result; resolved(id, result)
        return result
    }
    func deferUntilRequested() {
        guard !finished, acknowledgment == nil else { return }
        finished = true; resolved(id, false)
    }
}

