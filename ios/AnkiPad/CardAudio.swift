import UIKit
import AVFoundation
import AVKit
import UniformTypeIdentifiers

@MainActor final class CardAudio {
    private var player: AVAudioPlayer?
    private var video: AVPlayerViewController?
    private var videoObserver: NSObjectProtocol?
    private var videoDelegate: VideoDelegate?
    private let speech = AVSpeechSynthesizer()
    private let speechDelegate = SpeechDelegate()
    private var currentUtterance: AVSpeechUtterance?
    private var utteranceGeneration: UUID?
    private var pending: [[String: Any]] = []
    private var media: URL?
    private var delegate: AudioDelegate?
    private var generation = UUID()
    private var completion: (() -> Void)?
    init() {
        // Keep the synthesizer delegate alive across stop and media switches.
        // TextToSpeech may dispatch a cancelled utterance callback later.
        speechDelegate.finished = { [weak self] utterance in
            guard let self, self.currentUtterance === utterance,
                  self.utteranceGeneration == self.generation else { return }
            self.currentUtterance = nil; self.utteranceGeneration = nil
            self.advance()
        }
        speech.delegate = speechDelegate
    }
    var isPlaying: Bool { player?.isPlaying == true || speech.isSpeaking || video != nil }
    func append(_ tags: [[String: Any]], media: URL) {
        self.media = media
        pending += tags
        if !isPlaying { advance() }
    }
    func stop() {
        generation = UUID()
        completion = nil
        currentUtterance = nil; utteranceGeneration = nil
        pending = []; player?.stop(); player = nil; speech.stopSpeaking(at: .immediate)
        finishVideo(continueQueue: false)
    }
    private func finishVideo(continueQueue: Bool) {
        guard video != nil else { return }
        if let videoObserver { NotificationCenter.default.removeObserver(videoObserver) }
        videoObserver = nil
        let playbackGeneration = generation
        let old = video
        video = nil; videoDelegate = nil
        old?.delegate = nil
        old?.player?.pause()
        if old?.presentingViewController != nil {
            old?.dismiss(animated: true) { [weak self] in
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
        presenter.present(controller, animated: true) { avPlayer.play() }
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
    func play(_ tags: [[String: Any]], media: URL, completion: (() -> Void)? = nil) {
        stop()
        self.completion = completion
        self.media = media
        pending = tags
        advance()
    }
    private func advance() {
        guard !pending.isEmpty, let media else {
            let finished = completion
            completion = nil
            finished?()
            return
        }
        let playbackGeneration = generation
        let tag = pending.removeFirst()
        if let filename = tag["soundOrVideo"] as? String {
            let root = media.standardizedFileURL.resolvingSymlinksInPath()
            let url = root.appendingPathComponent(filename).standardizedFileURL.resolvingSymlinksInPath()
            guard url.path.hasPrefix(root.path + "/") else { advance(); return }
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback)
                if UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true {
                    if !playVideo(url) { advance() }
                    return
                }
                let audio = try AVAudioPlayer(contentsOf: url)
                let delegate = AudioDelegate { [weak self] in
                    guard let self, self.generation == playbackGeneration else { return }
                    self.advance()
                }
                self.delegate = delegate
                audio.delegate = delegate
                player = audio
                if !audio.play() { advance() }
            } catch { advance() }
        } else if let tts = tag["tts"] as? [String: Any], let text = tts["fieldText"] as? String {
            do { try AVAudioSession.sharedInstance().setCategory(.playback) }
            catch { advance(); return }
            let utterance = AVSpeechUtterance(string: text)
            let requested = tts["voices"] as? [String] ?? []
            let voices = AVSpeechSynthesisVoice.speechVoices()
            utterance.voice = requested.lazy.compactMap { name in voices.first { $0.identifier == name || $0.name == name } }.first ?? AVSpeechSynthesisVoice(language: tts["lang"] as? String)
            let speed = (tts["speed"] as? Double) ?? 1
            utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(speed)))
            currentUtterance = utterance
            utteranceGeneration = playbackGeneration
            speech.speak(utterance)
        } else { advance() }
    }
    private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
        var finished: (@MainActor (AVSpeechUtterance) -> Void)?
        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            Task { @MainActor in self.finished?(utterance) }
        }
    }
    private final class AudioDelegate: NSObject, AVAudioPlayerDelegate {
        let done: @MainActor () -> Void
        init(done: @escaping @MainActor () -> Void) { self.done = done }
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor in self.done() } }
    }
}
