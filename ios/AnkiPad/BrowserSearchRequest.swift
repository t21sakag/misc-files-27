import Foundation

/// Stable filter identity, distinct from the editable literal search string.
/// Card-state storage codes match AnkiDroid, not protobuf (buried is 3 vs 5).
enum BrowserSearchCardState: Int, Codable, CaseIterable, Hashable {
    case new = 0, learning = 1, review = 2, buried = 3, suspended = 4
    var searchValue: String {
        switch self {
        case .new: return "CARD_STATE_NEW"
        case .learning: return "CARD_STATE_LEARN"
        case .review: return "CARD_STATE_REVIEW"
        case .buried: return "CARD_STATE_BURIED"
        case .suspended: return "CARD_STATE_SUSPENDED"
        }
    }
}

enum BrowserSearchFlag: Int, Codable, CaseIterable, Hashable {
    case none = 0, red, orange, green, blue, pink, turquoise, purple
    var searchValue: String {
        switch self {
        case .none: return "FLAG_NONE"
        case .red: return "FLAG_RED"
        case .orange: return "FLAG_ORANGE"
        case .green: return "FLAG_GREEN"
        case .blue: return "FLAG_BLUE"
        case .pink: return "FLAG_PINK"
        case .turquoise: return "FLAG_TURQUOISE"
        case .purple: return "FLAG_PURPLE"
        }
    }
}

struct BrowserSearchRequest: Codable, Equatable, Hashable {
    enum Failure: Error { case invalidIdentifier, missingReference, invalidBackendResponse }
    var query: String = ""
    var deckIDs: [String] = []
    var flags: [BrowserSearchFlag] = []
    var tags: [String] = []
    var noteTypeIDs: [String] = []
    var cardStates: [BrowserSearchCardState] = []
    private enum CodingKeys: String, CodingKey {
        case query = "q", deckIDs = "did", flags = "f", tags = "t", noteTypeIDs = "ntid", cardStates = "s"
    }
    init(query: String = "", deckIDs: [String] = [], flags: [BrowserSearchFlag] = [], tags: [String] = [],
         noteTypeIDs: [String] = [], cardStates: [BrowserSearchCardState] = []) {
        self.query = query; self.deckIDs = deckIDs; self.flags = flags; self.tags = tags
        self.noteTypeIDs = noteTypeIDs; self.cardStates = cardStates
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        query = try values.decode(String.self, forKey: .query)
        deckIDs = try values.decodeIfPresent([String].self, forKey: .deckIDs) ?? []
        flags = try values.decodeIfPresent([BrowserSearchFlag].self, forKey: .flags) ?? []
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        noteTypeIDs = try values.decodeIfPresent([String].self, forKey: .noteTypeIDs) ?? []
        cardStates = try values.decodeIfPresent([BrowserSearchCardState].self, forKey: .cardStates) ?? []
    }
    var hasFilters: Bool { !deckIDs.isEmpty || !flags.isEmpty || !tags.isEmpty || !noteTypeIDs.isEmpty || !cardStates.isEmpty }
    var isEmpty: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasFilters }
    /// Missing IDs throw instead of silently broadening the user's search.
    func build(deckName: (String) throws -> String?, noteTypeName: (String) throws -> String?,
               backend: ([String: Any]) throws -> [String: Any]) throws -> String {
        func resolved(_ ids: [String], lookup: (String) throws -> String?, key: String) throws -> [[String: Any]] {
            try ids.map { id in
                guard let value = Int64(id), value > 0, String(value) == id else { throw Failure.invalidIdentifier }
                guard let name = try lookup(id), !name.isEmpty else { throw Failure.missingReference }
                return [key: name]
            }
        }
        var groups: [[String: Any]] = []
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isEmpty {
            groups.append(["parsableText": query.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
        func append(_ nodes: [[String: Any]]) {
            if !nodes.isEmpty { groups.append(["group": ["joiner": "OR", "nodes": nodes]]) }
        }
        append(try resolved(deckIDs, lookup: deckName, key: "deck"))
        append(flags.map { ["flag": $0.searchValue] })
        append(tags.map { ["tag": $0] })
        append(try resolved(noteTypeIDs, lookup: noteTypeName, key: "note"))
        append(cardStates.map { ["cardState": $0.searchValue] })
        guard let query = try backend(["group": ["joiner": "AND", "nodes": groups]])["val"] as? String else {
            throw Failure.invalidBackendResponse
        }
        return query
    }
}
