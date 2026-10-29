import Foundation

/// Incoming text is a draft, never an instruction to save a note. Plain text
/// and explicitly supplied HTML are kept distinct until inserted into fields.
struct IncomingNoteDraft: Identifiable, Sendable {
    let id = UUID()
    var front: String
    var back: String
    var tags: String?
    var isHTML: Bool
    var requiredFieldCount: Int { back.isEmpty ? 1 : 2 }
    var fields: [String] { [front, back].map { isHTML ? $0 : Self.plainField($0) } }

    init(front: String = "", back: String = "", tags: String? = nil, isHTML: Bool = false) {
        self.front = front; self.back = back; self.tags = tags; self.isHTML = isHTML
    }
    // AnkiDroid's SEND mapping uses subject/body, or body on the front if the
    // subject is empty. PROCESS_TEXT likewise populates only the front.
    init(subject: String, text: String, tags: String? = nil, isHTML: Bool = false) {
        self.init(front: subject.isEmpty ? text : subject, back: subject.isEmpty ? "" : text, tags: tags, isHTML: isHTML)
    }
    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "studyclient", parts.host?.lowercased() == "x-callback-url",
              parts.path == "/addnote" else { return nil }
        var values: [String: String] = [:]
        for pair in (parts.percentEncodedQuery ?? "").split(separator: "&", omittingEmptySubsequences: false) {
            let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = pieces.first, ["front", "back", "subject", "text", "tags", "html"].contains(String(key)), values[String(key)] == nil else { continue }
            let encoded = pieces.count > 1 ? String(pieces[1]) : ""
            guard let value = encoded.replacingOccurrences(of: "+", with: " ").removingPercentEncoding else { return nil }
            values[String(key)] = value
        }
        let html = ["1", "true"].contains(values["html"]?.lowercased() ?? "")
        if values["front"] != nil || values["back"] != nil {
            self.init(front: values["front"] ?? "", back: values["back"] ?? "", tags: values["tags"], isHTML: html)
        } else {
            self.init(subject: values["subject"] ?? "", text: values["text"] ?? "", tags: values["tags"], isHTML: html)
        }
    }
    private static func plainField(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}
