import Foundation

@main struct CardScriptLanguageSmoke {
    static func main() {
        let examples: [(String, String, Int)] = [
            ("en_US", "en-US", 2),
            ("en_US_#Latn", "en-US", 2),
            ("en_US_POSIX", "en-US", 1),
            ("en_GB", "en-US", 0),
            ("en", "en-US", 0),
            ("ja_JP", "ja-JP", 2),
            ("ja_JP", "en-US", -2),
            ("zz_ZZ", "en-US", -2),
            ("", "en-US", -2),
            ("en_US_POSIX_EXTRA", "en-US", -2),
            ("zh-Hant-TW", "zh-TW", 2),
            ("zh-Hant-TW", "zh-CN", 0)
        ]
        for (requested, selected, expected) in examples {
            precondition(CardScriptSpeechLanguage.support(requested: requested, selected: selected) == expected,
                         "Unexpected support for \(requested) -> \(selected)")
        }
        print("PASS: actual TTS locale comparison preserves exact/country/language/unsupported statuses and strips Java locale script extensions")
    }
}
