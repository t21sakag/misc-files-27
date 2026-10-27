import Foundation

@main struct SyncActivitySmoke {
    static func main() {
        let suite = "sync-activity-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SyncActivityStore(defaults: defaults)
        store.begin(profileID: "one")
        store.finish(profileID: "one")
        precondition(!store.consumeInterruption(profileID: "one"))
        store.begin(profileID: "one")
        store.interrupt(profileID: "one")
        store.finish(profileID: "one")
        let reopened = SyncActivityStore(defaults: UserDefaults(suiteName: suite)!)
        precondition(!reopened.consumeInterruption(profileID: "two"))
        precondition(reopened.consumeInterruption(profileID: "one"))
        precondition(!reopened.consumeInterruption(profileID: "one"))
        store.begin(profileID: "two") // Unclean termination leaves an active marker.
        precondition(reopened.consumeInterruption(profileID: "two"))
        print("PASS: normal completion, interrupted cleanup, relaunch and profile isolation")
    }
}
