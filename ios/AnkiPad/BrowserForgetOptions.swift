import Foundation

/// The browser's reset dialog keeps its own options, as AnkiDroid does. These
/// choices are independent of search state and are written only on confirmation.
struct BrowserForgetOptions: Codable, Equatable {
    enum Failure: Error { case invalidData, unsupportedVersion, invalidTargets }
    var restorePosition = true
    var resetCounts = false
    private struct Storage: Codable { var version = 1; var options: BrowserForgetOptions }

    static func load(key: String, defaults: UserDefaults = .standard) throws -> Self {
        guard defaults.object(forKey: key) != nil else { return Self() }
        guard let data = defaults.data(forKey: key) else { throw Failure.invalidData }
        let stored = try JSONDecoder().decode(Storage.self, from: data)
        guard stored.version == 1 else { throw Failure.unsupportedVersion }
        return stored.options
    }
    func save(key: String, defaults: UserDefaults = .standard) throws {
        _ = try Self.load(key: key, defaults: defaults)
        let data = try JSONEncoder().encode(Storage(options: self))
        defaults.set(data, forKey: key)
    }
    func arguments(cardIDs: [String]) throws -> [String: Any] {
        guard !cardIDs.isEmpty, Set(cardIDs).count == cardIDs.count,
              cardIDs.allSatisfy({ id in
                  guard let value = Int64(id), value > 0 else { return false }
                  return String(value) == id
              }) else { throw Failure.invalidTargets }
        // Android's Scheduler.forgetCards logs the change and omits context.
        return ["cardIds": cardIDs, "log": true, "restorePosition": restorePosition, "resetCounts": resetCounts]
    }
}
