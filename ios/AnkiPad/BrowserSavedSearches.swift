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

/// Anki's names compare literal code units. Swift String equality normalizes
/// Unicode, so keep the original bytes as part of every dictionary identity.
struct BrowserSavedSearchName: Hashable, Comparable, Sendable {
    let value: String
    private let literalBytes: Data

    init(_ value: String) {
        self.value = value
        literalBytes = Data(value.utf8)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value.utf16.lexicographicallyPrecedes(rhs.value.utf16)
    }
}

typealias BrowserSavedSearches = [BrowserSavedSearchName: String]

enum BrowserSavedSearchCoding {
    static func decode(_ data: Data) throws -> BrowserSavedSearches {
        let object = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        guard object is [String: Any], let text = String(data: data, encoding: .utf8) else {
            throw BrowserSavedSearchFailure.invalidData
        }
        // Validate JSON globally, then decode each scalar separately. A
        // Foundation dictionary would already merge distinct literal names.
        let source = text as NSString
        let pairs = try NSRegularExpression(pattern: #"("(?:[^"\\]|\\.)*")\s*:\s*("(?:[^"\\]|\\.)*")"#)
        func validGap(_ range: NSRange) -> Bool {
            source.substring(with: range).allSatisfy { $0.isWhitespace || "{},\u{FEFF}".contains($0) }
        }
        func string(_ range: NSRange) throws -> String {
            let token = Data(source.substring(with: range).utf8)
            guard let value = try JSONSerialization.jsonObject(with: token, options: .fragmentsAllowed) as? String else {
                throw BrowserSavedSearchFailure.invalidData
            }
            return value
        }
        var searches: BrowserSavedSearches = [:]
        var position = 0
        for match in pairs.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            guard validGap(NSRange(location: position, length: match.range.location - position)) else {
                throw BrowserSavedSearchFailure.invalidData
            }
            searches[BrowserSavedSearchName(try string(match.range(at: 1)))] = try string(match.range(at: 2))
            position = NSMaxRange(match.range)
        }
        guard validGap(NSRange(location: position, length: source.length - position)) else {
            throw BrowserSavedSearchFailure.invalidData
        }
        return searches
    }

    static func encode(_ searches: BrowserSavedSearches) throws -> Data {
        var data = Data("{".utf8)
        for (index, entry) in searches.sorted(by: { $0.key < $1.key }).enumerated() {
            if index > 0 { data.append(0x2c) }
            data.append(try JSONSerialization.data(withJSONObject: entry.key.value, options: .fragmentsAllowed))
            data.append(0x3a)
            data.append(try JSONSerialization.data(withJSONObject: entry.value, options: .fragmentsAllowed))
        }
        data.append(0x7d)
        return data
    }
}

extension Engine {
    func browserSavedSearches() throws -> BrowserSavedSearches {
        guard let data = try configData("savedFilters") else { return [:] }
        return try BrowserSavedSearchCoding.decode(data)
    }

    /// Read and write in one actor turn so a stale browser snapshot cannot
    /// replace another saved search or lose an intervening addition.
    func saveBrowserSearch(name: String, query: String) throws -> BrowserSavedSearches {
        guard !name.isEmpty else { throw BrowserSavedSearchFailure.emptyName }
        var searches = try browserSavedSearches()
        let key = BrowserSavedSearchName(name)
        guard searches[key] == nil else { throw BrowserSavedSearchFailure.duplicateName }
        searches[key] = query.trimmingCharacters(in: .whitespacesAndNewlines)
        try setConfigData("savedFilters", data: BrowserSavedSearchCoding.encode(searches))
        return searches
    }

    func removeBrowserSearches(_ names: [String]) throws -> BrowserSavedSearches {
        var searches = try browserSavedSearches()
        let previousCount = searches.count
        for name in names { searches.removeValue(forKey: BrowserSavedSearchName(name)) }
        if searches.count != previousCount {
            try setConfigData("savedFilters", data: BrowserSavedSearchCoding.encode(searches))
        }
        return searches
    }
}
