import Foundation

/// The read-only browser route supported by AnkiDroid's IntentHandler.
/// A missing search preserves normal browser defaults; an empty search means all.
struct BrowserLink: Equatable {
    let search: String?
    init(search: String?) { self.search = search }
    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["anki", "studyclient"].contains(parts.scheme?.lowercased() ?? ""),
              parts.host?.lowercased() == "x-callback-url", parts.path == "/browser" else { return nil }
        var search: String?
        // Android Uri.getQueryParameter uses the first search value and treats
        // an unescaped plus as a space. Percent-encoded plus remains literal.
        for pair in (parts.percentEncodedQuery ?? "").split(separator: "&", omittingEmptySubsequences: false) {
            let fields = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.first == "search" else { continue }
            let encoded = fields.count == 1 ? "" : String(fields[1])
            guard let decoded = encoded.replacingOccurrences(of: "+", with: " ").removingPercentEncoding else { return nil }
            search = decoded
            break
        }
        // Callback parameters are not dispatched. This route only opens a UI.
        self.search = search
    }
}

/// Keep the most recent browser request until the UI is ready. Rejected URLs
/// must neither consume nor overwrite a valid request waiting behind an editor.
struct BrowserLinkInbox {
    private(set) var pending: BrowserLink?
    @discardableResult mutating func receive(_ url: URL) -> Bool {
        guard let request = BrowserLink(url: url) else { return false }
        pending = request
        return true
    }
    mutating func take(canPresent: Bool) -> BrowserLink? {
        guard canPresent else { return nil }
        defer { pending = nil }
        return pending
    }
}
