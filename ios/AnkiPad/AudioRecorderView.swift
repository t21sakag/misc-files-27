import SwiftUI
import AVFoundation

@MainActor final class NoteAudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    @Published var recording = false
    @Published var file: URL?
    @Published var error: String?
    @Published private(set) var playing = false
    @Published private(set) var recordedDuration: TimeInterval = 0
    var duration: TimeInterval { recording ? recorder?.currentTime ?? 0 : recordedDuration }
    private var recorder: AVAudioRecorder?
    private var playback: AVAudioPlayer?
    private var ownsAudioSession = false
    private var permissionGeneration = UUID()
    @Published private(set) var requestingPermission = false
    func start() async {
        guard !requestingPermission, !recording else { return }
        finish()
        error = nil
        let generation = UUID()
        permissionGeneration = generation
        requestingPermission = true
        let granted = await AVAudioApplication.requestRecordPermission()
        guard permissionGeneration == generation else { return }
        requestingPermission = false
        guard granted else { error = "設定でAnkiPadのマイクへのアクセスを許可してください。"; return }
        do {
            discard()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            ownsAudioSession = true
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording-" + UUID().uuidString + ".m4a")
            let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            recorder.delegate = self
            self.recorder = recorder
            file = url
            guard recorder.record() else { throw EngineError(message: "録音を開始できませんでした。") }
            recording = true
        } catch {
            self.error = error.localizedDescription
            finish()
            discard()
        }
    }
    func stop() {
        if recording { recordedDuration = recorder?.currentTime ?? 0 }
        recorder?.stop()
        recording = false
    }
    func togglePreview() {
        guard !recording, file != nil else { return }
        if playback?.isPlaying == true { playback?.pause(); playing = false; return }
        guard let playback else { preview(); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            ownsAudioSession = true
            if playback.currentTime >= playback.duration { playback.currentTime = 0 }
            guard playback.play() else { throw EngineError(message: "録音を再生できませんでした。") }
            playing = true
        } catch { self.error = error.localizedDescription }
    }
    func preview() {
        guard let file, !recording else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            ownsAudioSession = true
            playback?.stop()
            playback = try AVAudioPlayer(contentsOf: file)
            playback?.delegate = self
            guard playback?.play() == true else { throw EngineError(message: "録音を再生できませんでした。") }
            playing = true
        }
        catch { self.error = error.localizedDescription }
    }
    func discard() {
        finish()
        stop(); playback?.stop(); playback = nil; recorder = nil
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
        recordedDuration = 0
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor in
            guard let current = self.playback, ObjectIdentifier(current) == identity else { return }
            self.playing = false
            if !flag { self.error = "録音の再生を完了できませんでした。" }
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let identity = ObjectIdentifier(player)
        let message = error?.localizedDescription ?? "録音を読み取れませんでした。"
        Task { @MainActor in
            guard let current = self.playback, ObjectIdentifier(current) == identity else { return }
            self.finish(); self.error = message
        }
    }
    private func invalidatePermissionRequest() {
        permissionGeneration = UUID()
        requestingPermission = false
    }
    func finish() {
        invalidatePermissionRequest()
        playback?.stop()
        playing = false
        stop()
        if ownsAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsAudioSession = false
        }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let message = error?.localizedDescription ?? "録音中にエラーが発生しました。"
        let failedRecorder = ObjectIdentifier(recorder)
        Task { @MainActor in
            guard let current = self.recorder, ObjectIdentifier(current) == failedRecorder else { return }
            self.finish()
            self.error = message
        }
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
                Text(recorder.recording ? "録音中" : "音声を録音")
                if recorder.recording { Button("停止", systemImage: "stop.circle") { recorder.stop() } }
                else {
                    Button(recorder.file == nil ? "録音を開始" : "録り直す", systemImage: "record.circle") { Task { await recorder.start() } }.disabled(recorder.requestingPermission)
                    if recorder.file != nil { Button("再生して確認", systemImage: "play.circle") { recorder.preview() } }
                }
                if saving { ProgressView() }
            }
            .disabled(saving).padding()
            .navigationTitle("音声を録音")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { recorder.discard(); dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("挿入") {
                    guard let file = recorder.file else { return }
                    recorder.stop(); saving = true
                    Task {
                        defer { saving = false }
                        do { try await insert(file); recorder.discard(); dismiss() }
                        catch { recorder.error = error.localizedDescription }
                    }
                }.disabled(recorder.recording || recorder.file == nil || saving) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { recorder.finish() }
            }
            .onDisappear { recorder.finish(); recorder.discard() }
            .alert("録音できませんでした", isPresented: Binding(get: { recorder.error != nil }, set: { if !$0 { recorder.error = nil } })) { Button("閉じる", role: .cancel) { recorder.error = nil } } message: { Text(recorder.error ?? "") }
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
                Text(recorder.recording ? "録音中" : "カードの音声と自分の発音を聞き比べられます。")
                TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                    Text("録音時間: \(recorder.duration, specifier: "%.1f")秒")
                        .monospacedDigit().accessibilityIdentifier("voice-recording-seconds")
                        .accessibilityValue(String(recorder.duration))
                }
                if recorder.recording {
                    Button("録音を停止", systemImage: "stop.circle") { model.saveReviewRecording() }
                        .accessibilityIdentifier("voice-stop")
                } else {
                    Button(recorder.file == nil ? "録音を開始" : "録り直す", systemImage: "record.circle") {
                        model.recordReviewVoice()
                    }.disabled(recorder.requestingPermission).accessibilityIdentifier("voice-record")
                    if recorder.file != nil {
                        Button(recorder.playing ? "録音を一時停止" : "録音を再生", systemImage: recorder.playing ? "pause.circle" : "play.circle") {
                            model.replayReviewVoice()
                        }.accessibilityIdentifier("voice-replay")
                        Button("聞き比べる（カード→録音）", systemImage: "arrow.right.circle") { model.compareReviewVoice() }
                            .disabled(!model.reviewVoiceHasReference).accessibilityIdentifier("voice-compare")
                        Button("録音を消す", role: .destructive) { model.stopCardAudioForRecognition(); recorder.discard() }
                            .accessibilityIdentifier("voice-discard")
                    }
                    Button("カードの音声を再生", systemImage: "speaker.wave.2") { model.playReviewVoiceReference() }
                        .disabled(!model.reviewVoiceHasReference).accessibilityIdentifier("voice-reference")
                }
                Text("録音はこのカードの練習用に一時保存します。次のカードに進むと削除します。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("自分の声")
            .overlay { keyboardCommands }
            .sheet(item: model.speechRequestBinding(inVoice: true), onDismiss: model.finishSpeechChoice) { request in
                ReviewSpeechVoiceView(model: model, request: request)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
            .onDisappear { recorder.finish() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { model.stopCardAudioForRecognition(); recorder.finish() }
                else if phase == .active { model.prepareVoiceSpeechContexts() }
            }
            .alert("録音できませんでした", isPresented: Binding(get: { recorder.error != nil }, set: { if !$0 { recorder.error = nil } })) {
                Button("閉じる", role: .cancel) { recorder.error = nil }
            } message: { Text(recorder.error ?? "") }
        }
    }
}
