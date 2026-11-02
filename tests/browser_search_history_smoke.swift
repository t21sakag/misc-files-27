import Foundation

@main struct BrowserSearchHistorySmoke {
    static func main() throws {
        let suite = "HistoryTest-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = "profile.default.browserSearchHistory", second = "profile.second.browserSearchHistory"
        defaults.set("kept", forKey: "unrelated")
        let legacy = ["  literal 日本語 *  ", "x", "x", " "]
        defaults.set(legacy, forKey: first)
        let loaded = try BrowserSearchHistory.entries(key: first, defaults: defaults)
        precondition(loaded.map(\.query) == [legacy[0], "x"])
        precondition(defaults.stringArray(forKey: first) == legacy, "Reading must not overwrite legacy data")
        let structured = BrowserSearchRequest(deckIDs: ["1"], flags: [.red], tags: ["alpha"])
        let migrated = try BrowserSearchHistory.remember(structured, key: first, defaults: defaults)
        precondition(migrated == [structured] + loaded && defaults.data(forKey: first) != nil)
        let reopened = UserDefaults(suiteName: suite)!
        let reloaded = try BrowserSearchHistory.entries(key: first, defaults: reopened)
        precondition(reloaded == migrated)
        for index in 0..<40 {
            try BrowserSearchHistory.remember(BrowserSearchRequest(query: "search-\(index)"), key: first, defaults: defaults)
        }
        let bounded = try BrowserSearchHistory.entries(key: first, defaults: defaults)
        precondition(bounded.count == 30 && bounded.first?.query == "search-39" && bounded.last?.query == "search-10")
        let request = BrowserSearchRequest(query: "search-15")
        let reordered = try BrowserSearchHistory.remember(request, key: first, defaults: defaults)
        precondition(reordered.first == request && reordered.count == 30 && Set(reordered).count == 30)
        let blank = try BrowserSearchHistory.remember(BrowserSearchRequest(query: " \n "), key: first, defaults: defaults)
        precondition(blank == reordered)
        try BrowserSearchHistory.remember(structured, key: second, defaults: defaults)
        let other = try BrowserSearchHistory.entries(key: second, defaults: defaults)
        precondition(other == [structured])
        let removed = try BrowserSearchHistory.remove(request, key: first, defaults: defaults)
        precondition(!removed.contains(request) && removed.count == 29)
        BrowserSearchHistory.clear(key: first, defaults: defaults)
        let cleared = try BrowserSearchHistory.entries(key: first, defaults: defaults)
        let isolated = try BrowserSearchHistory.entries(key: second, defaults: defaults)
        precondition(cleared.isEmpty && isolated == [structured])
        for damaged in [Data("broken".utf8), Data("{\"version\":2,\"entries\":[]}".utf8),
                        Data("{\"version\":1,\"entries\":[{\"q\":\"\",\"f\":[8]}]}".utf8)] {
            defaults.set(damaged, forKey: first)
            do { _ = try BrowserSearchHistory.remember(request, key: first, defaults: defaults); preconditionFailure("Invalid history was overwritten") }
            catch { precondition(defaults.data(forKey: first) == damaged) }
        }
        BrowserSearchHistory.clear(key: first, defaults: defaults)
        let ordered = BrowserSearchRequest(deckIDs: ["1", "2"])
        let reversed = BrowserSearchRequest(deckIDs: ["2", "1"])
        try BrowserSearchHistory.remember(ordered, key: first, defaults: defaults)
        let two = try BrowserSearchHistory.remember(reversed, key: first, defaults: defaults)
        precondition(two == [reversed, ordered], "Preserve source list equality")
        precondition(defaults.string(forKey: "unrelated") == "kept")
        print("PASS: actual defaults legacy migration preserves literals, MRU30, typed IDs, reload, profile isolation, deletion and corrupt/future data without overwriting it")
    }
}
