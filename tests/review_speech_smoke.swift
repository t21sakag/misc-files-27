import Foundation

@main struct ReviewSpeechSmoke {
    static func main() throws {
        let values = try LegacySpeechText.parse("<script>bad()</script><p>日本語 &amp; [...]</p><span>end</span>")
        precondition(values == [SpeechSnippet(text: "日本語 & 空欄 end", locale: "")])
        let localized = try LegacySpeechText.parse("<tts service='android' voice='en_US'>Hello</tts><tts SERVICE='ANDROID' voice='ja_JP'>日本語</tts>outside")
        precondition(localized == [SpeechSnippet(text: "Hello", locale: "en-US"), SpeechSnippet(text: "日本語", locale: "ja-JP")])
        precondition(LegacySpeechText.answerOnly("front<hr id=answer> answer") == "answer")
        precondition(LegacySpeechText.answerOnly("front<hr id=\"answer\"> answer") == "answer")
        precondition(LegacySpeechText.answerOnly("whole answer") == "whole answer")
        let empty = try LegacySpeechText.parse(" \n ")
        let nul = try LegacySpeechText.parse("before\0after")
        precondition(empty == [SpeechSnippet(text: "", locale: "")])
        precondition(nul == [SpeechSnippet(text: "before\u{FFFD}after", locale: "")])
        let name = "speech-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let question = ReviewSpeechScope(deckID: "20", ordinal: 1, cloze: false, side: .question)
        let answer = ReviewSpeechScope(deckID: "20", ordinal: 1, cloze: false, side: .answer)
        let other = ReviewSpeechScope(deckID: "20", ordinal: 2, cloze: false, side: .question)
        let filtered = ReviewSpeechScope(deckID: "99", originalDeckID: "20", ordinal: 1, cloze: false, side: .question)
        precondition(filtered == question)
        precondition(ReviewSpeechScope(deckID: "20", ordinal: 7, cloze: true, side: .question).template == 0)
        precondition(ReviewSpeechPreferences.load(profileID: "default", scope: question, defaults: defaults) == nil)
        let voice = ReviewSpeechChoice(mode: .voice, voiceID: "fixture.voice")
        try ReviewSpeechPreferences.save(voice, profileID: "default", scope: question, defaults: defaults)
        try ReviewSpeechPreferences.save(.off, profileID: "default", scope: answer, defaults: defaults)
        try ReviewSpeechPreferences.save(.system, profileID: "second", scope: question, defaults: defaults)
        precondition(ReviewSpeechPreferences.load(profileID: "default", scope: filtered, defaults: defaults) == voice)
        precondition(ReviewSpeechPreferences.load(profileID: "default", scope: answer, defaults: defaults) == .off)
        precondition(ReviewSpeechPreferences.load(profileID: "default", scope: other, defaults: defaults) == nil)
        precondition(ReviewSpeechPreferences.load(profileID: "second", scope: question, defaults: defaults) == .system)
        ReviewSpeechPreferences.remove(profileID: "second", defaults: defaults)
        precondition(ReviewSpeechPreferences.load(profileID: "second", scope: question, defaults: defaults) == nil)
        precondition(ReviewSpeechPreferences.load(profileID: "default", scope: question, defaults: defaults) == voice)
        print("PASS: actual inert HTML/C bridge; cloze blank/pure answer; persisted profile/deck/template/side isolation; filtered scope")
    }
}
