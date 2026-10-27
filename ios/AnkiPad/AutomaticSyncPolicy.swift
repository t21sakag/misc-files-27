import Foundation

struct AutomaticSyncPolicy {
    enum Event: Equatable { case foreground, background }
    private(set) var pending: Event?
    private var lastAttempt: [String: TimeInterval] = [:]
    mutating func discardPending() { pending = nil }
    mutating func request(_ event: Event, syncing: Bool) {
        guard !syncing else { return }
        if pending != .background { pending = event }
    }
    mutating func recordAttempt(profileID: String, uptime: TimeInterval) { lastAttempt[profileID] = uptime }
    mutating func take(profileID: String, enabled: Bool, hasAccount: Bool, canStart: Bool, uptime: TimeInterval) -> Event? {
        guard enabled && hasAccount else { pending = nil; return nil }
        guard let event = pending, canStart else { return nil }
        pending = nil
        if event == .foreground, let previous = lastAttempt[profileID], uptime - previous < 15 { return nil }
        return event
    }
}

struct LocalSyncState {
    let neverSynced: Bool
    let hasChanges: Bool
}
