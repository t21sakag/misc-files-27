import Foundation

/// The last browser request is independent of the recent-search MRU. Keeping
/// IDs here allows position restoration to resolve renamed decks and types.
enum BrowserSearchPosition {
    enum Failure: Error { case invalidData, unsupportedVersion }
    private struct Storage: Codable { var version = 1; var request: BrowserSearchRequest }

    static func request(key: String, defaults: UserDefaults = .standard) throws -> BrowserSearchRequest? {
        if let data = defaults.data(forKey: key) {
            let stored = try JSONDecoder().decode(Storage.self, from: data)
            guard stored.version == 1 else { throw Failure.unsupportedVersion }
            return stored.request
        }
        if let legacy = defaults.object(forKey: key) as? String { return BrowserSearchRequest(query: legacy) }
        guard defaults.object(forKey: key) == nil else { throw Failure.invalidData }
        return nil
    }

    static func initialRequest(query: String, explicit: Bool, defaultQuery: String, restore: Bool,
                               key: String, defaults: UserDefaults = .standard) throws -> BrowserSearchRequest {
        if explicit || !query.isEmpty { return BrowserSearchRequest(query: query) }
        if !defaultQuery.isEmpty { return BrowserSearchRequest(query: defaultQuery) }
        if restore, let last = try request(key: key, defaults: defaults) { return last }
        return BrowserSearchRequest()
    }

    static func save(_ request: BrowserSearchRequest, key: String, defaults: UserDefaults = .standard) throws {
        // Read first: a future version or damaged value must survive unchanged.
        _ = try self.request(key: key, defaults: defaults)
        let data = try JSONEncoder().encode(Storage(request: request))
        defaults.set(data, forKey: key)
    }
}
