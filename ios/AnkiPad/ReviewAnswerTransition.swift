import Foundation

/// Plain FrontSide cards can reveal their answer inside the existing document.
/// Dynamic templates and typed answers keep the full renderer lifecycle.
enum ReviewAnswerTransition {
    static func pendingHTML(question: String, answer: String) -> String? {
        guard !question.isEmpty, answer.hasPrefix(question) else { return nil }
        let suffix = String(answer.dropFirst(question.count))
        guard suffix.range(of: #"^\s*<hr\s+id\s*=\s*(?:answer|"answer"|'answer')\s*/?>"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        let tags = try! NSRegularExpression(pattern: #"<\s*/?\s*([a-zA-Z][\w:-]*)\b[^<>]*>"#)
        let allowed: Set<String> = ["div", "p", "br", "hr", "span", "font", "a", "b", "i", "strong", "em", "u", "small"]
        let range = NSRange(answer.startIndex..., in: answer)
        guard answer.filter({ $0 == "<" }).count == tags.numberOfMatches(in: answer, range: range),
              !answer.contains("<!--"), !answer.contains("\\("), !answer.contains("\\["), !answer.contains("$$"),
              answer.range(of: #"\son\w+\s*=|\[\[type:|id\s*=\s*["']?typeans\b"#, options: [.regularExpression, .caseInsensitive]) == nil,
              tags.matches(in: answer, range: range).allSatisfy({ match in
                  guard let name = Range(match.range(at: 1), in: answer) else { return false }
                  return allowed.contains(answer[name].lowercased())
              }) else { return nil }
        return question + "<div id=\"study-pending-answer\" inert aria-hidden=\"true\">" + suffix + "</div>"
    }
}
