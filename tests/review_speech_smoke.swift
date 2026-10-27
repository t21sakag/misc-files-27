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
        let voices = [InstalledSpeechVoice(id: "en", name: "English", language: "en-US"), InstalledSpeechVoice(id: "ja", name: "Japanese", language: "ja-JP")]
        let plain = [SpeechSnippet(text: "words", locale: "")]
        precondition(ReviewSpeechPlan.prepare(plain, choice: nil, voices: voices) == .needsChoice)
        precondition(ReviewSpeechPlan.prepare(plain, choice: .off, voices: voices) == .ready([]))
        precondition(ReviewSpeechPlan.prepare(plain, choice: .system, voices: voices) == .ready([ResolvedSpeechSnippet(text: "words", language: "", voiceID: nil)]))
        precondition(ReviewSpeechPlan.prepare(plain, choice: ReviewSpeechChoice(mode: .voice, voiceID: "ja"), voices: voices) == .ready([ResolvedSpeechSnippet(text: "words", language: "ja-JP", voiceID: "ja")]))
        let specified = [SpeechSnippet(text: "hello", locale: "en-US")]
        precondition(ReviewSpeechPlan.prepare(specified, choice: .off, voices: voices) == .ready([ResolvedSpeechSnippet(text: "hello", language: "en-US", voiceID: nil)]))
        precondition(ReviewSpeechPlan.prepare(plain, choice: ReviewSpeechChoice(mode: .voice, voiceID: "deleted"), voices: voices) == .needsChoice)
        let fallback = [SpeechSnippet(text: "regional", locale: "en-AU")]
        precondition(ReviewSpeechPlan.prepare(fallback, choice: .off, voices: voices) == .ready([ResolvedSpeechSnippet(text: "regional", language: "en-US", voiceID: nil)]))
        let iso = [SpeechSnippet(text: "three letter", locale: "eng")]
        precondition(ReviewSpeechPlan.prepare(iso, choice: .off, voices: voices) == .ready([ResolvedSpeechSnippet(text: "three letter", language: "en-US", voiceID: nil)]))
        let whole = try LegacySpeechText.parse("<tts service=android>inside</tts> outside", localized: false)
        precondition(whole == [SpeechSnippet(text: "inside outside", locale: "")])
        ReviewSpeechPreferences.setEnabled(true, profileID: "default", defaults: defaults)
        precondition(!ReviewSpeechPreferences.enabled(profileID: "second", defaults: defaults))
        let media = try LegacySpeechText.parse("hello [anki:play:q:0] [sound:file.wav] world")
        precondition(media == [SpeechSnippet(text: "hello world", locale: "")])
        print("PASS: actual inert HTML/C bridge; cloze blank/pure answer; persisted profile/deck/template/side isolation; filtered scope")
    }
}
