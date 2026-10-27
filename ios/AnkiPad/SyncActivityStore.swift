import Foundation

/// A marker survives suspension/termination before the sync operation can unwind.
struct SyncActivityStore {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ profileID: String) -> String { "sync.activity." + profileID }
    func begin(profileID: String) { defaults.set("active", forKey: key(profileID)) }
    func interrupt(profileID: String) { defaults.set("interrupted", forKey: key(profileID)) }
    func finish(profileID: String) {
        if defaults.string(forKey: key(profileID)) == "active" { defaults.removeObject(forKey: key(profileID)) }
    }
    func consumeInterruption(profileID: String) -> Bool {
        guard defaults.string(forKey: key(profileID)) != nil else { return false }
        defaults.removeObject(forKey: key(profileID))
        return true
    }
    func clear(profileID: String) { defaults.removeObject(forKey: key(profileID)) }
}
