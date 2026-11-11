import Foundation
import AVFoundation
import Speech

enum CardScriptEventKind: String {
    case speech = "ankiSttResult"
    case search = "ankiSearchCard"
    case userAction = "ankiPadUserAction"
    case hint = "ankiPadShowHint"
    case scrollPage = "ankiPadScrollPage"
}
struct CardScriptEvent {
    let id = UUID()
    let mutationKey: String
    let json: String
    var kind: CardScriptEventKind = .speech
}

@MainActor final class CardScriptRecognition {
    private var language: String?
    private var lifecycle = CardRecognitionSession()
    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasTap = false
    private var session: AudioSessionLease?
    private var callback: (([String]?, String?) -> Void)?
    func setLanguage(_ language: String) -> Bool { self.language = language; return true }
    func start(callback: @escaping ([String]?, String?) -> Void) async -> Bool {
        cancel()
        let token = lifecycle.begin()
        self.callback = callback
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard lifecycle.canStart(token) else { return false }
        guard authorization == .authorized else { callback(nil, "Speech recognition permission not granted."); cancel(); return false }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard lifecycle.canStart(token) else { return false }
        guard microphone else { callback(nil, "Record audio permission not granted."); cancel(); return false }
        let locale = language.map { Locale(identifier: $0) } ?? .current
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            callback(nil, "Speech recognition is not available on this device."); cancel(); return false
        }
        do {
            let identity = UUID()
            let lease = AudioSessionLease(id: identity) { [weak self] in
                Task { @MainActor in
                    guard let self, self.session?.id == identity else { return }
                    self.callback?(nil, "Audio input was interrupted.")
                    self.cancel()
                }
            }
            session = lease
            try await AudioSessionCoordinator.shared.prepare(.recognition, lease: lease)
            guard lifecycle.canStart(token), lease.isValid else { return false }
            lifecycle.didStart(token)
            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = false
            let node = engine.inputNode
            let format = node.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw EngineError(message: "Audio input is unavailable.") }
            self.engine = engine
            self.request = request
            self.recognizer = recognizer
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            hasTap = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let final = result?.isFinal == true
                let matches = result?.transcriptions.map(\.formattedString) ?? []
                let message = error?.localizedDescription
                Task { @MainActor in
                    guard let self, self.lifecycle.isCurrent(token) else { return }
                    if final {
                        self.callback?(matches.isEmpty ? nil : matches, matches.isEmpty ? "No speech recognition results found." : nil)
                        self.cancel()
                    } else if let message {
                        self.callback?(nil, message)
                        self.cancel()
                    }
                }
            }
            engine.prepare()
            try engine.start()
            return true
        } catch {
            guard lifecycle.isCurrent(token) else { return false }
            callback(nil, error.localizedDescription)
            cancel()
            return false
        }
    }
    @discardableResult func finish() -> Bool {
        lifecycle.stopInput()
        if engine == nil { callback = nil }
        engine?.stop()
        if hasTap { engine?.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio()
        deactivateSession()
        return true
    }
    func cancel() {
        lifecycle.cancel()
        finish()
        task?.cancel()
        task = nil; request = nil; engine = nil; recognizer = nil; callback = nil
    }
    private func deactivateSession() {
        guard let session else { return }
        AudioSessionCoordinator.shared.release(session, deactivate: true)
        self.session = nil
    }
}
