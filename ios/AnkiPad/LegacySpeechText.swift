import Foundation

struct SpeechSnippet: Equatable {
    let text: String
    let locale: String
}
struct SpeechTextError: LocalizedError {
    var errorDescription: String? { "カードの読み上げ用テキストを取得できませんでした。" }
}
private final class SpeechTextCollector { var values: [SpeechSnippet] = [] }

enum LegacySpeechText {
    static func parse(_ html: String, blank: String = "空欄", localized: Bool = true) throws -> [SpeechSnippet] {
        let collector = SpeechTextCollector()
        let callback: APSpeechSegmentCallback = { text, locale, context in
            guard let context else { return }
            let collector = Unmanaged<SpeechTextCollector>.fromOpaque(context).takeUnretainedValue()
            collector.values.append(SpeechSnippet(text: text.map { String(cString: $0) } ?? "", locale: locale.map { String(cString: $0) } ?? ""))
        }
        let readable = html.replacingOccurrences(of: #"\[(?:anki:play:[qa]:[0-9]+|sound:[^\]]+)\]"#, with: "", options: .regularExpression)
        let ok = readable.replacingOccurrences(of: "\0", with: "\u{FFFD}").withCString {
            let context = Unmanaged.passUnretained(collector).toOpaque()
            return localized ? ap_speech_parse_html($0, callback, context) : ap_speech_plain_html($0, callback, context)
        }
        guard ok == 1 else { throw SpeechTextError() }
        return collector.values.map {
            SpeechSnippet(text: $0.text.replacingOccurrences(of: "[...]", with: blank)
                .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " "),
                locale: $0.locale.replacingOccurrences(of: "_", with: "-"))
        }
    }
    static func answerOnly(_ html: String) -> String {
        for marker in ["<hr id=answer>", "<hr id=\"answer\">"] {
            if let range = html.range(of: marker) { return String(html[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return html
    }
}
