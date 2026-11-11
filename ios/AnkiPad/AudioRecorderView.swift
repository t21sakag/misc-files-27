import SwiftUI
import AVFoundation

@MainActor final class NoteAudioRecorder: NSObject, ObservableObject {
    @Published var recording = false
    @Published var file: URL?
    @Published var error: String?
    @Published private(set) var playing = false
    @Published private(set) var recordedDuration: TimeInterval = 0
    var duration: TimeInterval { recordedDuration }
    private var recorder: FileAudioRecorder?
    private var recordingFinalization: AudioFinalization<TimeInterval>?
    private var durationUpdates: Task<Void, Never>?
    private var playback: FileAudioPlayer?
    private var playbackEndedDuringStart = false
    private var session: AudioSessionLease?
    private var playbackPreparation: Task<Void, Never>?
    private var playbackGeneration = UUID()
    private var preparingPlayback = false
    private var permissionGeneration = UUID()
    @Published private(set) var requestingPermission = false
    private func sessionLease() -> AudioSessionLease {
        if let session, session.isValid { return session }
        let identity = UUID()
        let lease = AudioSessionLease(id: identity) { [weak self] in
            Task { @MainActor in
                guard let self, self.session?.id == identity else { return }
                self.finish()
            }
        }
        session = lease
        return lease
    }
    func start() async {
        guard !requestingPermission, !recording || recordingFinalization != nil else { return }
        await awaitFinalization()
        guard !requestingPermission, !recording else { return }
        finish()
        error = nil
        let generation = UUID()
        permissionGeneration = generation
        requestingPermission = true
        defer { if permissionGeneration == generation { requestingPermission = false } }
        let granted = await AVAudioApplication.requestRecordPermission()
        guard permissionGeneration == generation else { return }
        guard granted else { error = AppText.localized("設定でAnkiPadのマイクへのアクセスを許可してください。"); return }
        do {
            // The old file is replaced only after permission is granted. Do
            // not call discard(), which invalidates this in-flight request.
            if let file { try? FileManager.default.removeItem(at: file) }
            file = nil; recorder = nil; playback = nil; recordedDuration = 0
            let lease = sessionLease()
            try await AudioSessionCoordinator.shared.prepare(.recording, lease: lease)
            guard permissionGeneration == generation, lease.isValid else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording-" + UUID().uuidString + ".m4a")
            let worker = FileAudioRecorder(url: url)
            recorder = worker
            let started = try await AudioSessionCoordinator.shared.perform(lease: lease) { [weak self, weak worker] in
                guard let worker else { return false }
                return try worker.start(lease: lease) { [weak self, weak worker] message in
                    Task { @MainActor in
                        guard let self, let worker, self.recorder === worker else { return }
                        self.error = message ?? AppText.localized("録音中にエラーが発生しました。")
                        self.discard()
                    }
                }
            }
            guard permissionGeneration == generation, lease.isValid else { return }
            guard started else { throw EngineError(message: AppText.localized("録音を開始できませんでした。")) }
            file = url
            recording = true
            durationUpdates = Task { @MainActor [weak self, weak worker] in
                while !Task.isCancelled {
                    guard let self, let worker, self.recorder === worker else { return }
                    do {
                        let value = try await AudioSessionCoordinator.shared.perform(lease: lease) { worker.duration }
                        guard self.recorder === worker, !Task.isCancelled else { return }
                        self.recordedDuration = value
                        try await Task.sleep(nanoseconds: 200_000_000)
                    } catch { return }
                }
            }
        } catch {
            guard permissionGeneration == generation else { return }
            self.error = error.localizedDescription
            discard()
        }
    }
    private func awaitFinalization() async {
        guard let result = recordingFinalization else { return }
        let duration = await result.value()
        guard recordingFinalization === result else { return }
        recordedDuration = file == nil ? 0 : duration
        recording = false; recordingFinalization = nil
    }
    func finalizedFile() async -> URL? {
        await awaitFinalization()
        guard !recording, !requestingPermission, let file else { return nil }
        // The insert operation owns a copy. Closing the sheet or background
        // cleanup may discard the original while the engine is importing it.
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("recording-insert-" + UUID().uuidString + ".m4a")
        let copy = AudioSessionCoordinator.shared.finalize { () -> Result<URL, Error> in
            Result { try FileManager.default.copyItem(at: file, to: destination); return destination }
        }
        switch await copy.value() {
        case .success(let url): return url
        case .failure(let failure): error = failure.localizedDescription; return nil
        }
    }
    func stop() {
        durationUpdates?.cancel(); durationUpdates = nil
        guard let worker = recorder else {
            if recordingFinalization == nil { recording = false }
            return
        }
        recorder = nil
        let published = file == worker.url
        let result = AudioSessionCoordinator.shared.finalize {
            let duration = worker.stop()
            if !published { try? FileManager.default.removeItem(at: worker.url) }
            return duration
        }
        recordingFinalization = result
        Task { @MainActor [weak self] in await self?.awaitFinalization() }
    }
    func togglePreview() {
        guard !requestingPermission, !recording, file != nil else { return }
        if preparingPlayback || playing {
            playbackGeneration = UUID()
            playbackPreparation?.cancel(); playbackPreparation = nil
            if preparingPlayback, let session {
                AudioSessionCoordinator.shared.release(session, deactivate: false)
                self.session = nil
            }
            preparingPlayback = false
            if let playback { AudioSessionCoordinator.shared.cleanup { playback.pause() } }
            playing = false
        } else { preparePreview(reset: playback == nil) }
    }
    func preview() {
        guard !requestingPermission, !recording, file != nil else { return }
        preparePreview(reset: true)
    }
    private func preparePreview(reset: Bool) {
        guard let file else { return }
        playbackPreparation?.cancel()
        let generation = UUID(); playbackGeneration = generation
        let lease = sessionLease()
        if reset, let playback { AudioSessionCoordinator.shared.cleanup { playback.stop() }; self.playback = nil }
        let worker = playback ?? FileAudioPlayer()
        playback = worker
        preparingPlayback = true; playbackEndedDuringStart = false
        AudioSessionCoordinator.shared.cleanup { worker.pause() }
        playing = false
        playbackPreparation = Task { @MainActor [weak self] in
            do {
                await self?.awaitFinalization()
                try await AudioSessionCoordinator.shared.prepare(.playback, lease: lease)
                guard let self, self.playbackGeneration == generation, !Task.isCancelled else { return }
                guard lease.isValid else { self.finish(); return }
                let started = try await AudioSessionCoordinator.shared.perform(lease: lease) { [weak self] in
                    try worker.preview(file, reset: reset, lease: lease) { [weak self, weak worker] success, message in
                        Task { @MainActor in
                            guard let self, let worker, self.playbackGeneration == generation, self.playback === worker else { return }
                            if !success {
                                self.finish()
                                self.error = message ?? AppText.localized("録音の再生を完了できませんでした。")
                            } else if self.preparingPlayback { self.playbackEndedDuringStart = true }
                            else { self.playing = false }
                        }
                    }
                }
                guard self.playbackGeneration == generation, !Task.isCancelled else { return }
                guard lease.isValid else { self.finish(); return }
                self.preparingPlayback = false; self.playbackPreparation = nil
                guard started else { throw EngineError(message: AppText.localized("録音を再生できませんでした。")) }
                self.playing = !self.playbackEndedDuringStart
            } catch {
                guard let self, self.playbackGeneration == generation, !Task.isCancelled else { return }
                self.preparingPlayback = false; self.playbackPreparation = nil
                self.error = error.localizedDescription
            }
        }
    }
    func discard() {
        finish()
        if let file {
            AudioSessionCoordinator.shared.cleanup { try? FileManager.default.removeItem(at: file) }
        }
        file = nil
        recordedDuration = 0
    }
    private func invalidatePermissionRequest() {
        permissionGeneration = UUID()
        requestingPermission = false
    }
    func finish() {
        invalidatePermissionRequest()
        if let playback { AudioSessionCoordinator.shared.cleanup { playback.stop() } }
        playback = nil
        playing = false
        stop()
        playbackGeneration = UUID()
        playbackPreparation?.cancel(); playbackPreparation = nil; preparingPlayback = false
        if let session { AudioSessionCoordinator.shared.release(session, deactivate: true) }
        session = nil
    }

}
struct AudioRecorderView: View {
    let insert: (URL) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var recorder = NoteAudioRecorder()
    @State private var saving = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: recorder.recording ? "waveform" : "mic").font(.system(size: 60)).foregroundStyle(recorder.recording ? .red : .primary)
                Text(recorder.recording ? AppText.localized("録音中") : AppText.localized("音声を録音"))
                if recorder.recording {
                    Button(AppText.localized("停止"), systemImage: "stop.circle") { recorder.stop() }.accessibilityIdentifier("note-record-stop")
                    Button(AppText.localized("最初からやり直す"), systemImage: "arrow.counterclockwise") {
                        recorder.discard()
                        Task { await recorder.start() }
                    }.accessibilityIdentifier("note-record-restart")
                }
                else {
                    Button(recorder.file == nil ? AppText.localized("録音を開始") : AppText.localized("録り直す"), systemImage: "record.circle") { Task { await recorder.start() } }.disabled(recorder.requestingPermission).accessibilityIdentifier("note-record-start")
                    if recorder.file != nil {
                        Button(AppText.localized("再生して確認"), systemImage: "play.circle") { recorder.preview() }
                        Button(AppText.localized("最初に戻す"), systemImage: "arrow.counterclockwise", role: .destructive) { recorder.discard() }
                            .accessibilityIdentifier("note-record-restart")
                    }
                }
                TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                    Text(AppText.localized("録音時間: \(String(format: "%.1f", recorder.duration))秒"))
                        .monospacedDigit().accessibilityIdentifier("note-record-duration")
                        .accessibilityValue(String(recorder.duration))
                }
                if saving { ProgressView() }
            }
            .disabled(saving).padding()
            .studyThemeSurface().navigationTitle(AppText.localized("音声を録音"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppText.localized("キャンセル")) { recorder.discard(); dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button(AppText.localized("挿入")) {
                    recorder.stop(); saving = true
                    Task {
                        defer { saving = false }
                        guard let file = await recorder.finalizedFile() else { return }
                        defer { try? FileManager.default.removeItem(at: file) }
                        do { try await insert(file); recorder.discard(); dismiss() }
                        catch { recorder.error = error.localizedDescription }
                    }
                }.disabled(recorder.recording || recorder.file == nil || saving).accessibilityIdentifier("note-record-insert") }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { recorder.finish() }
            }
            .onDisappear { recorder.finish(); recorder.discard() }
            .alert(AppText.localized("録音できませんでした"), isPresented: Binding(get: { recorder.error != nil }, set: { if !$0 { recorder.error = nil } })) { Button(AppText.localized("閉じる"), role: .cancel) { recorder.error = nil } } message: { Text(recorder.error ?? "") }
        }
    }
}


/// A temporary comparison recording, deliberately separate from note media.
struct ReviewVoiceView: View {
    @ObservedObject var model: StudyModel
    @ObservedObject var recorder: NoteAudioRecorder
    @AppStorage("reviewKeyboardConfiguration") private var keyboardData = Data()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private var keyboardCommands: some View {
        let configuration = ReviewKeyboardConfiguration.load(keyboardData)
        return VStack {
            ForEach(ReviewKey.allCases) { key in
                let action = configuration.action(for: key)
                if [.recordVoice, .replayVoice, .saveVoice, .replay].contains(action) {
                    Button(action.title) {
                        switch action {
                        case .recordVoice: model.recordReviewVoice()
                        case .replayVoice: model.replayReviewVoice()
                        case .saveVoice: model.saveReviewRecording()
                        case .replay: model.playReviewVoiceReference()
                        default: break
                        }
                    }.keyboardShortcut(key.shortcut).disabled(recorder.requestingPermission || model.speechPreparing || model.speechRequest != nil)
                }
            }
        }.frame(width: 0, height: 0).clipped().opacity(0).accessibilityHidden(true)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: recorder.recording ? "waveform" : "mic")
                    .font(.system(size: 60))
                    .foregroundStyle(recorder.recording ? .red : .primary)
                Text(recorder.recording ? AppText.localized("録音中") : AppText.localized("カードの音声と自分の発音を聞き比べられます。"))
                TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                    Text(AppText.localized("録音時間: \(String(format: "%.1f", recorder.duration))秒"))
                        .monospacedDigit().accessibilityIdentifier("voice-recording-seconds")
                        .accessibilityValue(String(recorder.duration))
                }
                if recorder.recording {
                    Button(AppText.localized("録音を停止"), systemImage: "stop.circle") { model.saveReviewRecording() }
                        .accessibilityIdentifier("voice-stop")
                } else {
                    Button(recorder.file == nil ? AppText.localized("録音を開始") : AppText.localized("録り直す"), systemImage: "record.circle") {
                        model.recordReviewVoice()
                    }.disabled(recorder.requestingPermission).accessibilityIdentifier("voice-record")
                    if recorder.file != nil {
                        Button(recorder.playing ? AppText.localized("録音を一時停止") : AppText.localized("録音を再生"), systemImage: recorder.playing ? "pause.circle" : "play.circle") {
                            model.replayReviewVoice()
                        }.accessibilityIdentifier("voice-replay")
                        Button(AppText.localized("聞き比べる（カード→録音）"), systemImage: "arrow.right.circle") { model.compareReviewVoice() }
                            .disabled(!model.reviewVoiceHasReference).accessibilityIdentifier("voice-compare")
                        Button(AppText.localized("録音を消す"), role: .destructive) { model.stopCardAudioForRecognition(); recorder.discard() }
                            .accessibilityIdentifier("voice-discard")
                    }
                    Button(AppText.localized("カードの音声を再生"), systemImage: "speaker.wave.2") { model.playReviewVoiceReference() }
                        .disabled(!model.reviewVoiceHasReference).accessibilityIdentifier("voice-reference")
                }
                Text(AppText.localized("録音はこのカードの練習用に一時保存します。次のカードに進むと削除します。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
            .studyThemeSurface().navigationTitle(AppText.localized("自分の声"))
            .overlay { keyboardCommands }
            .sheet(item: model.speechRequestBinding(inVoice: true), onDismiss: model.finishSpeechChoice) { request in
                ReviewSpeechVoiceView(model: model, request: request)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(AppText.localized("閉じる")) { dismiss() } } }
            .onDisappear { recorder.finish() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { model.stopCardAudioForRecognition(); recorder.finish() }
                else if phase == .active { model.prepareVoiceSpeechContexts() }
            }
            .alert(AppText.localized("録音できませんでした"), isPresented: Binding(get: { recorder.error != nil }, set: { if !$0 { recorder.error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) { recorder.error = nil }
            } message: { Text(recorder.error ?? "") }
        }
    }
}

final class FileAudioRecorder: @unchecked Sendable {
    let url: URL
    private var recorder: AVAudioRecorder?
    private var delegate: Delegate?
    private var stoppedDuration: TimeInterval = 0
    init(url: URL) { self.url = url }
    var duration: TimeInterval { recorder?.currentTime ?? stoppedDuration }
    private static func trace(_ phase: String) {
        #if DEBUG
        guard UITestIsolation.namespace() != nil else { return }
        NSLog("audio.playback.trace phase=%@ main=%d", phase, Thread.isMainThread ? 1 : 0)
        #endif
    }
    func start(lease: AudioSessionLease, failed: @escaping @Sendable (String?) -> Void) throws -> Bool {
        guard lease.isValid else { return false }
        let native = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
        let delegate = Delegate(failed: failed)
        self.delegate = delegate; recorder = native; native.delegate = delegate
        guard lease.isValid else { _ = stop(); return false }
        Self.trace("recorder-record.begin")
        let started = native.record()
        Self.trace("recorder-record.end")
        guard lease.isValid else { _ = stop(); return false }
        return started
    }
    func stop() -> TimeInterval {
        guard let recorder else { return stoppedDuration }
        stoppedDuration = recorder.currentTime
        Self.trace("recorder-stop.begin")
        recorder.stop()
        Self.trace("recorder-stop.end")
        self.recorder = nil; delegate = nil
        return stoppedDuration
    }
    private final class Delegate: NSObject, AVAudioRecorderDelegate {
        let failed: @Sendable (String?) -> Void
        init(failed: @escaping @Sendable (String?) -> Void) { self.failed = failed }
        func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) { failed(error?.localizedDescription) }
    }
}
