import Foundation

enum BrowserFieldSearchMode: String, CaseIterable {
    case contains, exact, empty, nonEmpty, exists
    var needsText: Bool { self == .contains || self == .exact }
}

struct BrowserFieldSearchRequest {
    enum Failure: Error { case missingField, invalidBackendResponse }
    var fieldName: String
    var mode: BrowserFieldSearchMode
    var text: String
    var currentSearch: String = ""
    var combineWithCurrent = false

    // Backend-escape names and literal text before inserting our wildcards.
    func build(using backend: ([String: Any]) throws -> [String: Any]) throws -> String {
        guard !fieldName.isEmpty else { throw Failure.missingField }
        var marker: String
        repeat { marker = "FieldSearch" + UUID().uuidString.replacingOccurrences(of: "-", with: "") }
        while fieldName.contains(marker) || text.contains(marker)
        let before = marker + "Before", after = marker + "After"
        let input: String
        switch mode {
        case .contains: input = before + text + after
        case .exact: input = text
        case .empty: input = ""
        case .nonEmpty, .exists: input = before
        }
        guard var query = try backend(["field": ["fieldName": fieldName, "text": input]])["val"] as? String else {
            throw Failure.invalidBackendResponse
        }
        switch mode {
        case .contains: query = query.replacingOccurrences(of: before, with: "*").replacingOccurrences(of: after, with: "*")
        case .nonEmpty: query = query.replacingOccurrences(of: before, with: "_*")
        case .exists: query = query.replacingOccurrences(of: before, with: "*")
        case .exact, .empty: break
        }
        if combineWithCurrent && !currentSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let joined = try backend(["group": ["joiner": "AND", "nodes": [
                ["parsableText": currentSearch], ["parsableText": query]
            ]]])["val"] as? String else { throw Failure.invalidBackendResponse }
            query = joined
        }
        return query
    }
    /// Combine only the literal text parts. Stable filter IDs stay separate,
    /// so a displayed old deck name is never reapplied after a rename.
    func buildRequest(combining base: BrowserSearchRequest,
                      backend: ([String: Any]) throws -> [String: Any]) throws -> BrowserSearchRequest {
        var fieldOnly = self; fieldOnly.combineWithCurrent = false
        let fieldQuery = try fieldOnly.build(using: backend)
        guard combineWithCurrent else { return BrowserSearchRequest(query: fieldQuery) }
        var result = base
        if result.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.query = fieldQuery }
        else {
            guard let combined = try backend(["group": ["joiner": "AND", "nodes": [
                ["parsableText": result.query], ["parsableText": fieldQuery]
            ]]])["val"] as? String else { throw Failure.invalidBackendResponse }
            result.query = combined
        }
        return result
    }

}
