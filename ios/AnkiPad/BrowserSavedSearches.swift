import Foundation

enum BrowserSavedSearchFailure: LocalizedError {
    case emptyName, duplicateName, invalidData

    var errorDescription: String? {
        switch self {
        case .emptyName: AppText.localized("名前を入力してください。")
        case .duplicateName: AppText.localized("同じ名前の検索があります。")
        case .invalidData: AppText.localized("保存した検索を読み込めませんでした。")
        }
    }
}

extension Engine {
    func browserSavedSearches() throws -> [String: String] {
        guard let data = try configData("savedFilters") else { return [:] }
        guard let text = String(data: data, encoding: .utf8) else {
            throw BrowserSavedSearchFailure.invalidData
        }
        // Foundation dictionaries merge canonically equivalent Unicode keys.
        // Inspect complete JSON string tokens before writing so legacy names
        // that this representation cannot distinguish are preserved on disk.
        let strings = try NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#)
        var names = Set<String>()
        for match in strings.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { throw BrowserSavedSearchFailure.invalidData }
            if text[range.upperBound...].drop(while: \.isWhitespace).first != ":" { continue }
            let token = try JSONSerialization.jsonObject(with: Data(text[range].utf8), options: .fragmentsAllowed)
            guard let name = token as? String, names.insert(name).inserted else {
                throw BrowserSavedSearchFailure.invalidData
            }
        }
        let value = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        guard let searches = value as? [String: String] else { throw BrowserSavedSearchFailure.invalidData }
        return searches
    }

    /// Read and write in one actor turn so a stale browser snapshot cannot
    /// replace another saved search or lose an intervening addition.
    func saveBrowserSearch(name: String, query: String) throws -> [String: String] {
        guard !name.isEmpty else { throw BrowserSavedSearchFailure.emptyName }
        var searches = try browserSavedSearches()
        guard searches[name] == nil else { throw BrowserSavedSearchFailure.duplicateName }
        searches[name] = query.trimmingCharacters(in: .whitespacesAndNewlines)
        try setConfigValue("savedFilters", value: searches)
        return searches
    }

    func removeBrowserSearches(_ names: [String]) throws -> [String: String] {
        var searches = try browserSavedSearches()
        let previousCount = searches.count
        for name in names { searches.removeValue(forKey: name) }
        if searches.count != previousCount { try setConfigValue("savedFilters", value: searches) }
        return searches
    }
}
