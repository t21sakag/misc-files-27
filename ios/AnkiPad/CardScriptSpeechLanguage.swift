import Foundation

/// Android TTS language support values, compared against the voice actually
/// selected by the platform. A fallback to another language is not support.
enum CardScriptSpeechLanguage {
    static func identifier(_ requested: String) -> String {
        let base = String(requested.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
        guard base.split(separator: "_", omittingEmptySubsequences: false).count <= 3 else { return "" }
        return base
            .trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
            .replacingOccurrences(of: "_", with: "-")
    }
    static func support(requested: String, selected: String) -> Int {
        let wanted = Locale(identifier: identifier(requested))
        let actual = Locale(identifier: identifier(selected))
        guard let language = wanted.languageCode, !language.isEmpty,
              language.caseInsensitiveCompare(actual.languageCode ?? "") == .orderedSame else { return -2 }
        func equal(_ left: String?, _ right: String?) -> Bool {
            (left ?? "").caseInsensitiveCompare(right ?? "") == .orderedSame
        }
        guard equal(wanted.regionCode, actual.regionCode) else { return 0 }
        return equal(wanted.variantCode, actual.variantCode) ? 2 : 1
    }
}

