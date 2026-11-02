import Foundation

@main struct BrowserSearchHistorySmoke {
    static func main() {
        let suite = "HistoryTest-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = "profile.default.browserSearchHistory", second = "profile.second.browserSearchHistory"
        defaults.set("kept", forKey: "unrelated")
        for index in 0..<40 { BrowserSearchHistory.remember("search-\(index)", key: first, defaults: defaults) }
        let bounded = BrowserSearchHistory.entries(key: first, defaults: defaults)
        precondition(bounded.count == 30 && bounded.first == "search-39" && bounded.last == "search-10")
        let reordered = BrowserSearchHistory.remember("search-15", key: first, defaults: defaults)
        precondition(reordered.first == "search-15" && reordered.count == 30 && Set(reordered).count == 30)
        precondition(BrowserSearchHistory.remember(" \n ", key: first, defaults: defaults) == reordered)
        let literal = "  deck:\"日本語 & *\"  "
        BrowserSearchHistory.remember(literal, key: second, defaults: defaults)
        let restored = UserDefaults(suiteName: suite)!
        precondition(BrowserSearchHistory.entries(key: second, defaults: restored) == [literal])
        precondition(BrowserSearchHistory.entries(key: first, defaults: restored) == reordered)
        let removed = BrowserSearchHistory.remove("search-15", key: first, defaults: defaults)
        precondition(!removed.contains("search-15") && removed.count == 29)
        BrowserSearchHistory.clear(key: first, defaults: defaults)
        precondition(BrowserSearchHistory.entries(key: first, defaults: defaults).isEmpty)
        precondition(BrowserSearchHistory.entries(key: second, defaults: defaults) == [literal])
        defaults.set(["", "x", "x", " ", "y"], forKey: first)
        precondition(BrowserSearchHistory.entries(key: first, defaults: defaults) == ["x", "y"])
        defaults.set(42, forKey: first)
        precondition(BrowserSearchHistory.entries(key: first, defaults: defaults).isEmpty)
        precondition(defaults.string(forKey: "unrelated") == "kept")
        print("PASS: real defaults history preserves MRU30, dedup, literal queries, blank rejection, reload, profile isolation and individual/all deletion without touching other preferences")
    }
}
