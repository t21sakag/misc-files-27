import Foundation

/// Upstream `ShouldFetchMedia`: always, only on unmetered networks, or never.
enum SyncMediaFetch: String, CaseIterable, Identifiable {
    case always, unmetered, never
    var id: String { rawValue }
    var title: String {
        switch self {
        case .always: AppText.localized("常に取得")
        case .unmetered: AppText.localized("Wi-Fiなど従量課金でない回線のみ")
        case .never: AppText.localized("取得しない")
        }
    }
}

/// App-wide sync network settings, matching AnkiDroid's sync preferences screen.
struct SyncNetworkPreferences: Equatable {
    static let defaultTimeout = 60
    static let minimumTimeout = 30
    static let maximumTimeout = 600
    var allowMetered = false
    var mediaFetch: SyncMediaFetch = .always
    var showStatusBadge = true
    var ioTimeoutSecs = defaultTimeout

    static func load(_ defaults: UserDefaults = .standard) -> Self {
        var value = Self()
        value.allowMetered = defaults.object(forKey: "syncAllowMetered") as? Bool ?? false
        value.mediaFetch = (defaults.string(forKey: "syncFetchMedia")).flatMap(SyncMediaFetch.init(rawValue:)) ?? .always
        value.showStatusBadge = defaults.object(forKey: "syncShowStatusBadge") as? Bool ?? true
        value.ioTimeoutSecs = clampedTimeout(defaults.object(forKey: "syncIoTimeoutSecs") as? Int ?? defaultTimeout)
        return value
    }
    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(allowMetered, forKey: "syncAllowMetered")
        defaults.set(mediaFetch.rawValue, forKey: "syncFetchMedia")
        defaults.set(showStatusBadge, forKey: "syncShowStatusBadge")
        defaults.set(Self.clampedTimeout(ioTimeoutSecs), forKey: "syncIoTimeoutSecs")
    }
    static func clampedTimeout(_ value: Int) -> Int { min(maximumTimeout, max(minimumTimeout, value)) }
    /// Upstream blocks (manual) or defers (automatic) sync on a metered network unless allowed.
    func requiresMeteredConfirmation(metered: Bool) -> Bool { metered && !allowMetered }
    func syncsMedia(metered: Bool) -> Bool {
        switch mediaFetch {
        case .always: true
        case .unmetered: !metered
        case .never: false
        }
    }
}
