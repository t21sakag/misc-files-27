import Foundation

/// One profile-scoped preference value. Legacy strings are read as literal
/// queries and replaced only after a complete typed record encodes correctly.
enum BrowserSearchHistory {
    enum Failure: Error { case invalidData, unsupportedVersion }
    private struct Storage: Codable { var version = 1; var entries: [BrowserSearchRequest] }
    static let maximumEntries = 30
    private static func bounded(_ values: [BrowserSearchRequest]) -> [BrowserSearchRequest] {
        var seen = Set<BrowserSearchRequest>()
        return Array(values.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(maximumEntries))
    }
    static func entries(key: String, defaults: UserDefaults = .standard) throws -> [BrowserSearchRequest] {
        if let data = defaults.data(forKey: key) {
            let stored = try JSONDecoder().decode(Storage.self, from: data)
            guard stored.version == 1 else { throw Failure.unsupportedVersion }
            return bounded(stored.entries)
        }
        if let legacy = defaults.stringArray(forKey: key) { return bounded(legacy.map { BrowserSearchRequest(query: $0) }) }
        guard defaults.object(forKey: key) == nil else { throw Failure.invalidData }
        return []
    }
    private static func save(_ values: [BrowserSearchRequest], key: String, defaults: UserDefaults) throws {
        let data = try JSONEncoder().encode(Storage(entries: values))
        defaults.set(data, forKey: key)
    }
    @discardableResult static func remember(_ request: BrowserSearchRequest, key: String,
                                             defaults: UserDefaults = .standard) throws -> [BrowserSearchRequest] {
        var values = try entries(key: key, defaults: defaults)
        guard !request.isEmpty else { return values }
        values.removeAll { $0 == request }; values.insert(request, at: 0)
        values = bounded(values); try save(values, key: key, defaults: defaults); return values
    }
    @discardableResult static func remove(_ request: BrowserSearchRequest, key: String,
                                           defaults: UserDefaults = .standard) throws -> [BrowserSearchRequest] {
        let values = try entries(key: key, defaults: defaults).filter { $0 != request }
        try save(values, key: key, defaults: defaults); return values
    }
    static func clear(key: String, defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }
}
