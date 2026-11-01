import Foundation
import AVFoundation

/// JavaScript TTS has an independent queue, matching AnkiDroid's JavaScriptTTS.
@MainActor final class CardScriptSpeech {
    private let synthesizer = AVSpeechSynthesizer()
    private var voice: AVSpeechSynthesisVoice?
    private var pitch: Float = 1
    private var rate: Float = 1
    private var session: AudioSessionLease?
    private var preparation: Task<Void, Never>?
    private var generation = UUID()
    private var pending: [AVSpeechUtterance] = []
    var isSpeaking: Bool { preparation != nil || !pending.isEmpty || synthesizer.isSpeaking }
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
    @discardableResult func stop() -> Int {
        generation = UUID()
        preparation?.cancel(); preparation = nil; pending.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        if let session { AudioSessionCoordinator.shared.release(session, deactivate: false) }
        session = nil
        return 0
    }
    func speak(_ text: String, queueMode: Int) -> Int {
        guard [0, 1].contains(queueMode), text.utf16.count <= 4000 else { return -1 }
        if queueMode == 0 { stop() }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.pitchMultiplier = pitch
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * rate))
        pending.append(utterance)
        guard preparation == nil else { return 0 }
        let token = generation
        let lease: AudioSessionLease
        if let session, session.isValid { lease = session }
        else {
            let identity = UUID()
            lease = AudioSessionLease(id: identity) { [weak self] in
                Task { @MainActor in
                    guard let self, self.session?.id == identity else { return }
                    self.stop()
                }
            }
            session = lease
        }
        preparation = Task { @MainActor [weak self] in
            do {
                try await AudioSessionCoordinator.shared.prepare(.playback, lease: lease)
                guard let self, self.generation == token, !Task.isCancelled else { return }
                guard lease.isValid else { self.stop(); return }
                self.preparation = nil
                let queued = self.pending; self.pending.removeAll()
                for utterance in queued { self.synthesizer.speak(utterance) }
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.stop()
            }
        }
        // As with the Android TTS API, success accepts the queued request;
        // native synthesis completion remains asynchronous.
        return 0
    }
}
