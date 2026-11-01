import UIKit
import AVFoundation
import AVKit
import UniformTypeIdentifiers

#if DEBUG
@MainActor enum NativeAudioDiagnostics {
    static var successfulCompletions = 0
    static var successfulSpeechCompletions = 0
    static var lastCompletedSpeechVoiceID = ""
    static func completed(_ success: Bool) {
        guard success, UITestIsolation.namespace() != nil,
              ProcessInfo.processInfo.arguments.contains("--uitest-audio-note") else { return }
        successfulCompletions += 1
    }
    static func speechCompleted(voiceID: String) {
        guard UITestIsolation.namespace() != nil,
              ProcessInfo.processInfo.arguments.contains("--uitest-speech-choice") else { return }
        successfulSpeechCompletions += 1
        lastCompletedSpeechVoiceID = voiceID
    }
}
#endif

@MainActor final class CardAudio {
    private var filePlayer: FileAudioPlayer?
    private var filePlaying = false
    private var fileFinishedDuringStart = false
    private var video: AVPlayerViewController?
    private var videoObserver: NSObjectProtocol?
    private var videoDelegate: VideoDelegate?
    private let speech = AVSpeechSynthesizer()
    private let speechDelegate = SpeechDelegate()
    private var currentUtterance: AVSpeechUtterance?
    private var utteranceGeneration: UUID?
    private var pending: [[String: Any]] = []
    private var preferredVoices: [String: AVSpeechSynthesisVoice] = [:]
    private var media: URL?
    private var generation = UUID()
    private var completion: (() -> Void)?
    private var session: AudioSessionLease?
    private var preparation: Task<Void, Never>?
    private var preparing = false
    init() {
        // Keep the synthesizer delegate alive across stop and media switches.
        // TextToSpeech may dispatch a cancelled utterance callback later.
        speechDelegate.finished = { [weak self] utterance in
            guard let self, self.currentUtterance === utterance,
                  self.utteranceGeneration == self.generation else { return }
            #if DEBUG
            NativeAudioDiagnostics.speechCompleted(voiceID: utterance.voice?.identifier ?? "")
            #endif
            self.currentUtterance = nil; self.utteranceGeneration = nil
            self.advance()
        }
        speech.delegate = speechDelegate
    }
    private func tracePlayback(_ phase: String) {
        #if DEBUG
        guard UITestIsolation.namespace() != nil || NSClassFromString("XCTestCase") != nil else { return }
        NSLog("audio.playback.trace phase=%@ main=%d", phase, Thread.isMainThread ? 1 : 0)
        #endif
    }
    var isPreparing: Bool { preparing }
    // Preparing belongs to the queue lifetime, so wait-for-audio cannot race startup.
    var isPlaying: Bool { preparing || filePlaying || speech.isSpeaking || video != nil }
    func append(_ tags: [[String: Any]], media: URL) {
        self.media = media
        pending += tags
        if !isPlaying { advance() }
    }
    func stop() {
        generation = UUID()
        preparation?.cancel(); preparation = nil; preparing = false
        if let session { AudioSessionCoordinator.shared.release(session, deactivate: false) }
        session = nil
        completion = nil
        preferredVoices = [:]
        currentUtterance = nil; utteranceGeneration = nil
        pending = []
        clearFilePlayer()
        tracePlayback("speech-stop.begin")
        speech.stopSpeaking(at: .immediate)
        tracePlayback("speech-stop.end")
        finishVideo(continueQueue: false)
    }
    private func finishVideo(continueQueue: Bool) {
        guard let old = video else { return }
        if let videoObserver { NotificationCenter.default.removeObserver(videoObserver) }
        videoObserver = nil
        let playbackGeneration = generation
        video = nil; videoDelegate = nil
        old.delegate = nil
        old.player?.pause()
        if old.presentingViewController != nil {
            StudyMotion.dismiss(old) { [weak self] in
                guard let self, self.generation == playbackGeneration else { return }
                if continueQueue { self.advance() }
            }
        } else if continueQueue { advance() }
    }
    private func playVideo(_ url: URL) -> Bool {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return false }
        while let presented = presenter.presentedViewController { presenter = presented }
        let controller = AVPlayerViewController()
        let avPlayer = AVPlayer(url: url)
        controller.player = avPlayer
        let playbackGeneration = generation
        let delegate = VideoDelegate { [weak self] in
            guard let self, self.generation == playbackGeneration else { return }
            self.finishVideo(continueQueue: true)
        }
        videoDelegate = delegate
        controller.delegate = delegate
        video = controller
        videoObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: avPlayer.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == playbackGeneration else { return }
                self.finishVideo(continueQueue: true)
            }
        }
        StudyMotion.present(controller, from: presenter) { avPlayer.play() }
        return true
    }
    private final class VideoDelegate: NSObject, AVPlayerViewControllerDelegate {
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }
        func playerViewController(_ playerViewController: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            Task { @MainActor in
                coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.done() }
            }
        }
    }
    func play(_ tags: [[String: Any]], media: URL, voices: [String: AVSpeechSynthesisVoice] = [:], completion: (() -> Void)? = nil) {
        stop()
        self.completion = completion
        preferredVoices = voices
        self.media = media
        pending = tags
        advance()
    }
    private func advance() {
        // A late completion from a revoked owner must not restart its queue.
        if let session, !session.isValid { stop(); return }
        guard !pending.isEmpty, let media else {
            clearFilePlayer()
            if let session { AudioSessionCoordinator.shared.release(session, deactivate: false) }
            session = nil
            let finished = completion
            completion = nil
            finished?()
            return
        }
        let playbackGeneration = generation
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
        preparing = true
        preparation = Task { @MainActor [weak self] in
            do {
                try await AudioSessionCoordinator.shared.prepare(.playback, lease: lease)
                guard let self, self.generation == playbackGeneration, !Task.isCancelled else { return }
                guard lease.isValid else { self.stop(); return }
                self.preparing = false; self.preparation = nil
                let tag = self.pending.removeFirst()
                self.playPrepared(tag, media: media, playbackGeneration: playbackGeneration)
            } catch {
                guard let self, self.generation == playbackGeneration, !Task.isCancelled else { return }
                self.preparing = false; self.preparation = nil
                if !lease.isValid { self.stop(); return }
                // Match the existing queue policy for an unplayable item.
                self.pending.removeFirst()
                self.advance()
            }
        }
    }
    private func playPrepared(_ tag: [String: Any], media: URL, playbackGeneration: UUID) {
        if let filename = tag["soundOrVideo"] as? String {
            let root = media.standardizedFileURL.resolvingSymlinksInPath()
            let url = root.appendingPathComponent(filename).standardizedFileURL.resolvingSymlinksInPath()
            guard url.path.hasPrefix(root.path + "/") else { advance(); return }
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true {
                if !playVideo(url) { advance() }
                return
            }
            startFile(url, playbackGeneration: playbackGeneration)
        } else if let tts = tag["tts"] as? [String: Any], let text = tts["fieldText"] as? String {
            let utterance = AVSpeechUtterance(string: text)
            let requested = tts["voices"] as? [String] ?? []
            let voices = AVSpeechSynthesisVoice.speechVoices()
            utterance.voice = requested.lazy.compactMap { name in self.preferredVoices[name] ?? AVSpeechSynthesisVoice(identifier: name) ?? voices.first { $0.identifier == name || $0.name == name } }.first ?? AVSpeechSynthesisVoice(language: tts["lang"] as? String)
            let speed = (tts["speed"] as? Double) ?? 1
            utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(speed)))
            currentUtterance = utterance
            utteranceGeneration = playbackGeneration
            tracePlayback("speech-play.begin")
            speech.speak(utterance)
            tracePlayback("speech-play.end")
        } else { advance() }
    }
    private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
        var finished: (@MainActor (AVSpeechUtterance) -> Void)?
        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            Task { @MainActor in self.finished?(utterance) }
        }
    }
    private func clearFilePlayer() {
        if let filePlayer { AudioSessionCoordinator.shared.cleanup { filePlayer.stop() } }
        filePlayer = nil; filePlaying = false; fileFinishedDuringStart = false
    }
    private func startFile(_ url: URL, playbackGeneration: UUID) {
        guard let lease = session, lease.isValid else { stop(); return }
        clearFilePlayer()
        let worker = FileAudioPlayer()
        filePlayer = worker; preparing = true
        preparation = Task { @MainActor [weak self] in
            do {
                let started = try await AudioSessionCoordinator.shared.perform(lease: lease) {
                    try worker.play(url, lease: lease) { [weak self, weak worker] in
                        Task { @MainActor in
                            guard let self, let worker, self.generation == playbackGeneration,
                                  self.filePlayer === worker else { return }
                            if self.preparing { self.fileFinishedDuringStart = true }
                            else { self.filePlaying = false; self.advance() }
                        }
                    }
                }
                guard let self, self.generation == playbackGeneration, self.filePlayer === worker,
                      !Task.isCancelled else { return }
                guard lease.isValid else { self.stop(); return }
                self.preparing = false; self.preparation = nil
                self.filePlaying = started && !self.fileFinishedDuringStart
                if !self.filePlaying { self.advance() }
            } catch {
                guard let self, self.generation == playbackGeneration, self.filePlayer === worker,
                      !Task.isCancelled else { return }
                self.preparing = false; self.preparation = nil
                if lease.isValid { self.advance() } else { self.stop() }
            }
        }
    }
}

/// All native player access belongs to AudioSessionCoordinator's executor.
/// Each clip has its own instance; stale cleanup cannot stop a replacement.
final class FileAudioPlayer: @unchecked Sendable {
    private var player: AVAudioPlayer?
    private var delegate: Delegate?
    private static func trace(_ phase: String) {
        #if DEBUG
        guard UITestIsolation.namespace() != nil || NSClassFromString("XCTestCase") != nil else { return }
        NSLog("audio.playback.trace phase=%@ main=%d", phase, Thread.isMainThread ? 1 : 0)
        #endif
    }
    func play(_ url: URL, lease: AudioSessionLease, finished: @escaping @Sendable () -> Void) throws -> Bool {
        try preview(url, reset: true, lease: lease) { _, _ in finished() }
    }
    func preview(_ url: URL, reset: Bool, lease: AudioSessionLease,
                 completed: @escaping @Sendable (Bool, String?) -> Void) throws -> Bool {
        guard lease.isValid else { return false }
        if reset || player == nil {
        Self.trace("player-init.begin")
        let audio = try AVAudioPlayer(contentsOf: url)
        Self.trace("player-init.end")
        player = audio
        }
        guard let audio = player else { return false }
        let delegate = Delegate(done: completed)
        self.delegate = delegate; audio.delegate = delegate
        if audio.currentTime >= audio.duration { audio.currentTime = 0 }
        guard lease.isValid else { stop(); return false }
        Self.trace("player-play.begin")
        let started = audio.play()
        Self.trace("player-play.end")
        guard lease.isValid else { stop(); return false }
        return started
    }
    func pause() {
        Self.trace("player-pause.begin")
        player?.pause()
        Self.trace("player-pause.end")
    }
    func stop() {
        Self.trace("player-stop.begin")
        player?.stop(); player = nil; delegate = nil
        Self.trace("player-stop.end")
    }
    private final class Delegate: NSObject, AVAudioPlayerDelegate {
        let done: @Sendable (Bool, String?) -> Void
        init(done: @escaping @Sendable (Bool, String?) -> Void) { self.done = done }
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            #if DEBUG
            Task { @MainActor in NativeAudioDiagnostics.completed(flag) }
            #endif
            done(flag, nil)
        }
        func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { done(false, error?.localizedDescription) }
    }
}
