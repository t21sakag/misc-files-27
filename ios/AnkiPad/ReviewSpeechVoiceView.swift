import SwiftUI

struct ReviewSpeechVoiceView: View {
    @ObservedObject var model: StudyModel
    let request: ReviewSpeechRequest
    @State private var choice: ReviewSpeechChoice
    @State private var query = ""
    @State private var error: String?
    init(model: StudyModel, request: ReviewSpeechRequest) {
        self.model = model; self.request = request
        _choice = State(initialValue: ReviewSpeechPreferences.load(profileID: request.profileID, scope: request.context.scope) ?? .system)
    }
    private var voices: [InstalledSpeechVoice] {
        request.voices.filter { query.isEmpty || $0.name.localizedStandardContains(query) || $0.language.localizedStandardContains(query) }
            .sorted { ($0.language, $0.name, $0.id) < ($1.language, $1.name, $1.id) }
    }
    private func row(_ value: ReviewSpeechChoice, title: String, id: String) -> some View {
        Button { model.audio.stop(); choice = value } label: {
            HStack { Text(title).foregroundStyle(.primary); Spacer(); if value == choice { Image(systemName: "checkmark") } }
                .frame(maxWidth: .infinity).contentShape(Rectangle())
        }.accessibilityIdentifier("speech-choice-" + id).accessibilityValue(choice == value ? "選択中" : "")
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(.system, title: "システムの音声", id: "system")
                    row(.off, title: "自動読み上げをしない", id: "off")
                } footer: {
                    Text("このデッキの" + (request.context.scope.side == .question ? "表面" : "裏面") + "の音声を設定します。カードが指定した言語を優先します。")
                }
                Section("利用できる音声") {
                    ForEach(voices, id: \.id) { voice in
                        row(ReviewSpeechChoice(mode: .voice, voiceID: voice.id), title: voice.name + " · " + voice.language, id: voice.id)
                    }
                }
            }
            .accessibilityIdentifier("speech-voices-list")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "音声・言語を検索")
            .navigationTitle("読み上げ音声")
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                        Button(model.audio.isPlaying ? "試聴を停止" : "試聴", systemImage: model.audio.isPlaying ? "stop.circle" : "play.circle") {
                            do {
                                if model.audio.isPlaying { model.audio.stop() }
                                else { try model.previewSpeechChoice(request, choice: choice) }
                            } catch { self.error = error.localizedDescription }
                        }.disabled(choice.mode == .off).accessibilityIdentifier("speech-preview")
                            .accessibilityValue(model.audio.isPlaying ? "再生中" : "停止中")
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { model.speechRequest = nil }.accessibilityIdentifier("speech-cancel") }
                ToolbarItem(placement: .confirmationAction) { Button("適用") {
                    do { try model.applySpeechChoice(request, choice: choice) } catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("speech-apply") }
            }
            .alert("音声を設定できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}
