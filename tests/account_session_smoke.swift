import Foundation

// Only the Keychain boundary and view model shell are substituted. The
// account transition itself is compiled from the production extension.
enum DeleteFailure: Error { case unavailable }
@MainActor enum AccountStore {
    static var calls: [String] = []
    static var failing = false
    static func delete(profileID: String) throws {
        calls.append(profileID)
        if failing { throw DeleteFailure.unavailable }
    }
}
@MainActor final class StudyModel {
    var busy = false
    let currentProfileID: String
    let preferencePrefix: String
    var account: String? = "old-account"
    var lastSync: Date? = Date(timeIntervalSince1970: 123)
    var syncStatus = "pending replacement"
    var syncDecision: String? = "old-server-directions-and-usn"
    var chooseFullSync = true
    var confirmDirection: Bool? = true
    var meteredSyncPrompt = true
    var error: String?
    init(id: String, prefix: String) { currentProfileID = id; preferencePrefix = prefix }
    func profilePreferenceKey(_ key: String) -> String { preferencePrefix + key }
}
@main struct AccountSessionChecks {
    @MainActor static func main() {
        let prefix = "account-session-check-" + UUID().uuidString + "."
        let otherKey = prefix + "other.lastSync"
        defer {
            UserDefaults.standard.removeObject(forKey: prefix + "lastSync")
            UserDefaults.standard.removeObject(forKey: otherKey)
        }
        let model = StudyModel(id: "selected-profile", prefix: prefix)
        UserDefaults.standard.set(123, forKey: prefix + "lastSync")
        UserDefaults.standard.set(456, forKey: otherKey)
        model.busy = true
        model.logout()
        precondition(AccountStore.calls.isEmpty && model.account != nil && model.syncDecision != nil)
        model.busy = false
        AccountStore.failing = true
        model.logout()
        precondition(AccountStore.calls == ["selected-profile"] && model.error != nil)
        precondition(model.account == "old-account" && model.lastSync != nil && model.syncDecision != nil)
        precondition(model.chooseFullSync && model.confirmDirection == true && model.meteredSyncPrompt)
        precondition(UserDefaults.standard.integer(forKey: prefix + "lastSync") == 123)
        AccountStore.failing = false
        model.logout()
        precondition(AccountStore.calls == ["selected-profile", "selected-profile"])
        precondition(model.account == nil && model.lastSync == nil && model.syncStatus.isEmpty)
        precondition(model.syncDecision == nil && !model.chooseFullSync && model.confirmDirection == nil && !model.meteredSyncPrompt)
        precondition(UserDefaults.standard.object(forKey: prefix + "lastSync") == nil)
        precondition(UserDefaults.standard.integer(forKey: otherKey) == 456)
        print("PASS: production logout clears account-owned sync directions only after successful Keychain deletion; busy/failure preserve state and other profile timestamp")
    }
}
