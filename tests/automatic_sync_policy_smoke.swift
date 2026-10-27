import Foundation

@main struct AutomaticSyncPolicySmoke {
    static func main() {
        let state = LocalSyncState(neverSynced: false, hasChanges: true, modification: "101")
        precondition(!state.applyingCleanStamp("101").hasChanges)
        precondition(state.applyingCleanStamp("100").hasChanges)
        precondition(state.applyingCleanStamp(nil).hasChanges)
        var policy = AutomaticSyncPolicy()
        policy.request(.foreground, syncing: false)
        precondition(policy.take(profileID: "a", enabled: true, hasAccount: true, canStart: false, uptime: 100) == nil)
        precondition(policy.pending == .foreground)
        precondition(policy.take(profileID: "a", enabled: true, hasAccount: true, canStart: true, uptime: 100) == .foreground)
        policy.recordAttempt(profileID: "a", uptime: 100)
        policy.request(.foreground, syncing: false)
        precondition(policy.take(profileID: "a", enabled: true, hasAccount: true, canStart: true, uptime: 101) == nil)
        policy.request(.background, syncing: false)
        policy.request(.foreground, syncing: false)
        precondition(policy.take(profileID: "a", enabled: true, hasAccount: true, canStart: true, uptime: 102) == .background)
        policy.request(.foreground, syncing: false)
        precondition(policy.take(profileID: "b", enabled: true, hasAccount: true, canStart: true, uptime: 103) == .foreground)
        policy.request(.background, syncing: true)
        precondition(policy.pending == nil)
        policy.request(.foreground, syncing: false)
        precondition(policy.take(profileID: "a", enabled: false, hasAccount: true, canStart: true, uptime: 200) == nil && policy.pending == nil)
        policy.request(.foreground, syncing: false)
        precondition(policy.take(profileID: "a", enabled: true, hasAccount: false, canStart: true, uptime: 201) == nil && policy.pending == nil)
        print("PASS: deferred events, foreground cooldown, background priority, profile isolation, disabled/no-account/ongoing-sync guards")
    }
}
