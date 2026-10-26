import Foundation
import AVFoundation

/// JavaScript TTS has an independent queue, matching AnkiDroid's JavaScriptTTS.
@MainActor final class CardScriptSpeech {
    private let synthesizer = AVSpeechSynthesizer()
    private var voice: AVSpeechSynthesisVoice?
    private var pitch: Float = 1
    private var rate: Float = 1
    var isSpeaking: Bool { synthesizer.isSpeaking }
    func setLanguage(_ language: String) -> Int {
        let code = language.replacingOccurrences(of: "_", with: "-")
        guard let selected = AVSpeechSynthesisVoice(language: code) else { return -2 }
        voice = selected
        return selected.language.caseInsensitiveCompare(code) == .orderedSame ? 2 : 0
    }
    func setPitch(_ value: Float) -> Int {
        guard value.isFinite, value > 0 else { return -1 }
        pitch = min(2, max(0.5, value))
        return 0
    }
    func setRate(_ value: Float) -> Int {
        guard value.isFinite, value > 0 else { return -1 }
        rate = value
        return 0
    }
    @discardableResult func stop() -> Int { synthesizer.stopSpeaking(at: .immediate); return 0 }
    func speak(_ text: String, queueMode: Int) -> Int {
        guard [0, 1].contains(queueMode), text.utf16.count <= 4000 else { return -1 }
        if queueMode == 0 { stop() }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            utterance.pitchMultiplier = pitch
            utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * rate))
            synthesizer.speak(utterance)
            return 0
        } catch { return -1 }
    }
}
