import SwiftUI
import AVFoundation

@MainActor final class NoteAudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var recording = false
    @Published var file: URL?
    @Published var error: String?
    private var recorder: AVAudioRecorder?
    private var playback: AVAudioPlayer?
    private var ownsAudioSession = false
    private var permissionGeneration = UUID()
    @Published private(set) var requestingPermission = false
    func start() async {
        guard !requestingPermission else { return }
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
    func stop() { recorder?.stop(); recording = false }
    func preview() {
        guard let file, !recording else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            ownsAudioSession = true
            playback = try AVAudioPlayer(contentsOf: file)
            guard playback?.play() == true else { throw EngineError(message: "録音を再生できませんでした。") }
        }
        catch { self.error = error.localizedDescription }
    }
    func discard() {
        finish()
        stop(); playback?.stop(); playback = nil; recorder = nil
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
    }
    private func invalidatePermissionRequest() {
        permissionGeneration = UUID()
        requestingPermission = false
    }
    func finish() {
        invalidatePermissionRequest()
        playback?.stop()
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
    @ObservedObject var recorder: NoteAudioRecorder
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: recorder.recording ? "waveform" : "mic")
                    .font(.system(size: 60))
                    .foregroundStyle(recorder.recording ? .red : .primary)
                Text(recorder.recording ? "録音中" : "自分の発音を録音して聞き比べられます。")
                if recorder.recording {
                    Button("録音を停止", systemImage: "stop.circle") { recorder.stop() }
                } else {
                    Button(recorder.file == nil ? "録音を開始" : "録り直す", systemImage: "record.circle") {
                        Task { await recorder.start() }
                    }.disabled(recorder.requestingPermission)
                    if recorder.file != nil {
                        Button("録音を再生", systemImage: "play.circle") { recorder.preview() }
                        Button("録音を消す", role: .destructive) { recorder.discard() }
                    }
                }
                Text("録音は次のカードに進むと削除されます。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("自分の声")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
            .onDisappear { recorder.finish() }
            .onChange(of: scenePhase) { _, phase in if phase == .background { recorder.finish() } }
            .alert("録音できませんでした", isPresented: Binding(get: { recorder.error != nil }, set: { if !$0 { recorder.error = nil } })) {
                Button("閉じる", role: .cancel) { recorder.error = nil }
            } message: { Text(recorder.error ?? "") }
        }
    }
}
