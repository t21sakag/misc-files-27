import Foundation

/// Local query history. The caller supplies the existing profile preference
/// key so another profile never inherits searches. Queries are never logged.
/// Structured filter-chip history remains separate from this raw-query adapter.
enum BrowserSearchHistory {
    static let maximumEntries = 30
    static func entries(key: String, defaults: UserDefaults = .standard) -> [String] {
        var seen = Set<String>()
        return Array((defaults.stringArray(forKey: key) ?? []).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0).inserted
        }.prefix(maximumEntries))
    }
    @discardableResult static func remember(_ query: String, key: String, defaults: UserDefaults = .standard) -> [String] {
        var values = entries(key: key, defaults: defaults)
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return values }
        values.removeAll { $0 == query }; values.insert(query, at: 0)
        values = Array(values.prefix(maximumEntries)); defaults.set(values, forKey: key)
        return values
    }
    @discardableResult static func remove(_ query: String, key: String, defaults: UserDefaults = .standard) -> [String] {
        let values = entries(key: key, defaults: defaults).filter { $0 != query }
        defaults.set(values, forKey: key); return values
    }
    static func clear(key: String, defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }
}
