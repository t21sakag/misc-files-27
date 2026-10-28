import Foundation

@main
struct SyncNetworkPreferencesSmoke {
    static func main() {
        let suite = "sync-network-preferences-smoke-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let initial = SyncNetworkPreferences.load(defaults)
        precondition(initial == SyncNetworkPreferences(), "upstream defaults: metered off, media always, badge on, 60s")
        precondition(initial.requiresMeteredConfirmation(metered: true) && !initial.requiresMeteredConfirmation(metered: false))
        precondition(initial.syncsMedia(metered: true) && initial.syncsMedia(metered: false))

        var changed = initial
        changed.allowMetered = true
        changed.mediaFetch = .unmetered
        changed.showStatusBadge = false
        changed.ioTimeoutSecs = 5
        changed.save(defaults)
        let restored = SyncNetworkPreferences.load(defaults)
        precondition(!restored.requiresMeteredConfirmation(metered: true))
        precondition(!restored.syncsMedia(metered: true) && restored.syncsMedia(metered: false))
        precondition(!restored.showStatusBadge && restored.mediaFetch == .unmetered)
        precondition(restored.ioTimeoutSecs == SyncNetworkPreferences.minimumTimeout, "timeout is clamped to the upstream minimum")
        precondition(SyncNetworkPreferences.clampedTimeout(100_000) == SyncNetworkPreferences.maximumTimeout)

        var never = restored
        never.mediaFetch = .never
        precondition(!never.syncsMedia(metered: false))
        defaults.set("bogus", forKey: "syncFetchMedia")
        precondition(SyncNetworkPreferences.load(defaults).mediaFetch == .always)
        print("sync network preferences smoke passed")
    }
}
