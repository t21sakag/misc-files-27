import Foundation

struct FieldImageReference: Identifiable {
    var id: Int { range.location }
    let source: String
    let range: NSRange
    private static func decodeEntities(_ value: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]+|#[0-9]+|amp|quot|apos|lt|gt|nbsp);"#) else { return value }
        let result = NSMutableString(string: value)
        let text = value as NSString
        for match in expression.matches(in: value, range: NSRange(location: 0, length: text.length)).reversed() {
            let entity = text.substring(with: match.range(at: 1))
            let replacement: String?
            if entity.hasPrefix("#") {
                let hex = entity.hasPrefix("#x")
                let digits = entity.dropFirst(hex ? 2 : 1)
                replacement = UInt32(digits, radix: hex ? 16 : 10).flatMap { UnicodeScalar($0) }.map { String($0) }
            } else {
                replacement = ["amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">", "nbsp": "\u{00a0}"][entity]
            }
            if let replacement { result.replaceCharacters(in: match.range, with: replacement) }
        }
        return result as String
    }
    static func extract(_ html: String) -> [Self] {
        // Skip comments and raw-text elements before considering an image tag.
        let tagPattern = #"<!--.*?(?:-->|\z)|<(script|style|textarea|title)\b(?:[^"'<>]|"[^"]*"|'[^']*')*>.*?(?:</\1\s*>|\z)|(<img(?=\s|/?>)(?:[^"'<>]|"[^"]*"|'[^']*')*>)"#
        let attributePattern = #"([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?"#
        guard let tags = try? NSRegularExpression(pattern: tagPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let attributes = try? NSRegularExpression(pattern: attributePattern) else { return [] }
        let text = html as NSString
        return tags.matches(in: html, range: NSRange(location: 0, length: text.length)).compactMap { tag in
            let tagRange = tag.range(at: 2)
            guard tagRange.location != NSNotFound else { return nil }
            let tagText = text.substring(with: tagRange) as NSString
            let body = NSRange(location: 4, length: tagText.length - 5)
            for attribute in attributes.matches(in: tagText as String, range: body) {
                guard tagText.substring(with: attribute.range(at: 1)).lowercased() == "src" else { continue }
                guard let group = (2...4).first(where: { attribute.range(at: $0).location != NSNotFound }) else { return nil }
                let local = attribute.range(at: group)
                let range = NSRange(location: tagRange.location + local.location, length: local.length)
                let decoded = decodeEntities(text.substring(with: range))
                let source = decoded.removingPercentEncoding ?? decoded
                guard !source.isEmpty, !source.contains("/"), !source.contains("\\"), !source.contains(":"), source != ".", source != "..",
                      !source.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
                return Self(source: source, range: range)
            }
            return nil
        }
    }
}
struct FieldImageSelection: Identifiable {
    let id = UUID()
    let field: Int
    let html: String
    let images: [FieldImageReference]
}
