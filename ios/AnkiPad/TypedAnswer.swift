import Foundation

struct TypedAnswerSpec {
    let expected: String
    let combining: Bool
    let noSuggest: Bool
    let font: String
    let size: Int
}
enum TypedAnswerMarkup {
    static let expression = try! NSRegularExpression(pattern: #"\[\[type:(.+?)\]\]"#)
    static func field(in html: String) -> String? {
        let range = NSRange(html.startIndex..., in: html)
        guard let match = expression.firstMatch(in: html, range: range), let field = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[field])
    }
    static func replace(in html: String, with replacement: String) -> String {
        var output = html
        let matches = expression.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for match in matches.reversed() {
            if let range = Range(match.range, in: output) { output.replaceSubrange(range, with: replacement) }
        }
        return output
    }
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
    }
}
extension Engine {
    func typingSpec(question: String, noteID: String, ordinal: Int) throws -> TypedAnswerSpec? {
        guard var field = TypedAnswerMarkup.field(in: question) else { return nil }
        var combining = true
        var cloze = false
        var noSuggest = false
        while true {
            if field.hasPrefix("nc:") { combining = false; field.removeFirst(3) }
            else if field.hasPrefix("cloze:") { cloze = true; field.removeFirst(6) }
            else if field.hasPrefix("nosuggest:") { noSuggest = true; field.removeFirst(10) }
            else { break }
        }
        let note = try call("NotesService.GetNote", ["nid": noteID])
        let schema = try call("NotetypesService.GetNotetype", ["ntid": note["notetypeId"] as? String ?? "0"])
        let definitions = schema["fields"] as? [[String: Any]] ?? []
        guard let index = definitions.firstIndex(where: { $0["name"] as? String == field }),
              let fields = note["fields"] as? [String], fields.indices.contains(index) else {
            throw EngineError(message: "入力解答のフィールドが見つかりません: \(field)")
        }
        var expected = fields[index]
        if cloze { expected = try call("CardRenderingService.ExtractClozeForTyping", ["text": expected, "ordinal": ordinal + 1])["val"] as? String ?? "" }
        expected = try call("CardRenderingService.StripAvTags", ["val": expected])["val"] as? String ?? ""
        expected = try call("CardRenderingService.StripHtml", ["text": expected])["val"] as? String ?? ""
        let config = definitions[index]["config"] as? [String: Any] ?? [:]
        return TypedAnswerSpec(expected: expected, combining: combining, noSuggest: noSuggest,
            font: config["fontName"] as? String ?? "-apple-system", size: config["fontSize"] as? Int ?? 20)
    }
    func compareTyped(_ card: StudyCard, provided: String) throws -> String {
        guard let spec = card.typing else { return card.answer }
        let result = try call("CardRenderingService.CompareAnswer", ["expected": spec.expected, "provided": provided, "combining": spec.combining])
        return TypedAnswerMarkup.replace(in: card.answer, with: result["val"] as? String ?? "")
    }
}
