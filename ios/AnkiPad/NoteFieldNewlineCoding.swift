import Foundation

enum NoteFieldNewlineCoding {
    static func fromHTML(_ html: String, replaceNewlines: Bool) -> String {
        guard replaceNewlines else { return html }
        return html.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
    }

    static func toHTML(_ text: String, replaceNewlines: Bool) -> String {
        guard replaceNewlines else { return text }
        return text.replacingOccurrences(of: "\r\n", with: "<br>").replacingOccurrences(of: "\n", with: "<br>")
    }
}
