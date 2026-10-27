import Foundation

struct InstalledSpeechVoice: Equatable {
    let id: String
    let name: String
    let language: String
}
struct ResolvedSpeechSnippet: Equatable {
    let text: String
    let language: String
    let voiceID: String?
    var avTag: [String: Any] {
        let tts: [String: Any] = ["fieldText": text, "lang": language, "voices": voiceID.map { [$0] } ?? [], "speed": 1.0]
        return ["tts": tts]
    }
}
enum ReviewSpeechPlan: Equatable {
    case needsChoice
    case ready([ResolvedSpeechSnippet])
    static func prepare(_ snippets: [SpeechSnippet], choice: ReviewSpeechChoice?, voices: [InstalledSpeechVoice]) -> Self {
        func normalize(_ value: String) -> String {
            Locale.canonicalLanguageIdentifier(from: value).replacingOccurrences(of: "_", with: "-").lowercased()
        }
        var result: [ResolvedSpeechSnippet] = []
        for snippet in snippets where !snippet.text.isEmpty {
            let requested = normalize(snippet.locale)
            let exact = voices.filter { normalize($0.language) == requested }
            let language = requested.split(separator: "-").first.map(String.init) ?? ""
            let candidates = !exact.isEmpty ? exact : voices.filter { normalize($0.language).split(separator: "-").first.map(String.init) == language }
            if !snippet.locale.isEmpty && !candidates.isEmpty {
                let selected = choice?.mode == .voice ? candidates.first { $0.id == choice?.voiceID } : nil
                let locale = candidates[0].language
                result.append(ResolvedSpeechSnippet(text: snippet.text, language: locale, voiceID: selected?.id))
                continue
            }
            guard let choice else { return .needsChoice }
            switch choice.mode {
            case .off: continue
            case .system: result.append(ResolvedSpeechSnippet(text: snippet.text, language: "", voiceID: nil))
            case .voice:
                guard let selected = voices.first(where: { $0.id == choice.voiceID }) else { return .needsChoice }
                result.append(ResolvedSpeechSnippet(text: snippet.text, language: selected.language, voiceID: selected.id))
            }
        }
        return .ready(result)
    }
}
