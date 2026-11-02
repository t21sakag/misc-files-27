import Foundation

@main struct BrowserSearchPositionSmoke {
    static func main() throws {
        let suite = "PositionTest-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "profile.default.lastBrowserSearch", second = "profile.second.lastBrowserSearch"
        let missing = try BrowserSearchPosition.request(key: key, defaults: defaults)
        precondition(missing == nil)
        let literal = "  deck:Old 日本語 *  "
        defaults.set(literal, forKey: key)
        let legacy = try BrowserSearchPosition.request(key: key, defaults: defaults)
        precondition(legacy == BrowserSearchRequest(query: literal))
        precondition(defaults.object(forKey: key) as? String == literal)
        let structured = BrowserSearchRequest(query: "unchanged", deckIDs: ["42"], flags: [.red], tags: ["日本語"], noteTypeIDs: ["7"], cardStates: [.buried])
        try BrowserSearchPosition.save(structured, key: key, defaults: defaults)
        let reopened = UserDefaults(suiteName: suite)!
        let restored = try BrowserSearchPosition.request(key: key, defaults: reopened)
        precondition(restored == structured)
        let selected = BrowserSearchPosition.initialRequest(query: "", explicit: false, defaultQuery: "")
        precondition(selected == BrowserSearchRequest(), "A new browser must not reuse a closed session's filters")
        let isolated = try BrowserSearchPosition.request(key: second, defaults: defaults)
        precondition(isolated == nil)
        try BrowserSearchPosition.save(BrowserSearchRequest(), key: second, defaults: defaults)
        let empty = try BrowserSearchPosition.request(key: second, defaults: defaults)
        precondition(empty == BrowserSearchRequest(), "An explicit empty last search must replace a previous filter")
        for invalid: Any in [Data("broken".utf8), Data("{\"version\":2,\"request\":{\"q\":\"x\"}}".utf8), Data("{\"version\":1,\"request\":{\"q\":\"\",\"f\":[8]}}".utf8), ["unexpected"]] {
            defaults.set(invalid, forKey: key)
            let original = defaults.object(forKey: key) as! NSObject
            let explicitEmpty = BrowserSearchPosition.initialRequest(query: "", explicit: true, defaultQuery: "default")
            precondition(explicitEmpty == BrowserSearchRequest())
            let existing = BrowserSearchPosition.initialRequest(query: "current", explicit: false, defaultQuery: "default")
            precondition(existing.query == "current")
            let configured = BrowserSearchPosition.initialRequest(query: "", explicit: false, defaultQuery: "default")
            precondition(configured.query == "default")
            let disabled = BrowserSearchPosition.initialRequest(query: "", explicit: false, defaultQuery: "")
            precondition(disabled == BrowserSearchRequest(), "New browser policy must not read corrupt session storage")
            do {
                try BrowserSearchPosition.save(structured, key: key, defaults: defaults)
                preconditionFailure("Unsupported position data was overwritten")
            } catch { precondition(original.isEqual(defaults.object(forKey: key))) }
        }
        let untouched = try BrowserSearchPosition.request(key: second, defaults: defaults)
        precondition(untouched == BrowserSearchRequest())
        print("PASS: last-session snapshot preserves literals, stable IDs and profiles; fresh/explicit/default browser policy is independent of session data and scheduler preferences")
    }
}
