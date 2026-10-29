import SwiftUI

struct ReviewSpeechVoiceView: View {
    @ObservedObject var model: StudyModel
    let request: ReviewSpeechRequest
    @State private var choice: ReviewSpeechChoice
    @State private var query = ""
    @State private var error: String?
    @FocusState private var searchFocused: Bool
    init(model: StudyModel, request: ReviewSpeechRequest) {
        self.model = model; self.request = request
        _choice = State(initialValue: ReviewSpeechPreferences.load(profileID: request.profileID, scope: request.context.scope) ?? .system)
    }
    private var voices: [InstalledSpeechVoice] {
        request.voices.filter { query.isEmpty || $0.name.localizedStandardContains(query) || $0.language.localizedStandardContains(query) }
            .sorted { ($0.language, $0.name, $0.id) < ($1.language, $1.name, $1.id) }
    }
    private func row(_ value: ReviewSpeechChoice, title: String, id: String) -> some View {
        Button { searchFocused = false; model.audio.stop(); choice = value } label: {
            HStack { Text(title).foregroundStyle(.primary); Spacer(); if value == choice { Image(systemName: "checkmark") } }
                .frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.borderless).accessibilityIdentifier("speech-choice-" + id).accessibilityValue(choice == value ? AppText.localized("選択中") : "")
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(AppText.localized("音声・言語を検索"), text: $query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($searchFocused).submitLabel(.done).onSubmit { searchFocused = false }
                        .accessibilityIdentifier("speech-search")
                }
                Section {
                    row(.system, title: AppText.localized("システムの音声"), id: "system")
                    row(.off, title: AppText.localized("自動読み上げをしない"), id: "off")
                } footer: {
                    Text(request.context.scope.side == .question
                         ? AppText.localized("このデッキの表面の音声を設定します。カードが指定した言語を優先します。")
                         : AppText.localized("このデッキの裏面の音声を設定します。カードが指定した言語を優先します。"))
                }
                Section(AppText.localized("利用できる音声")) {
                    ForEach(voices, id: \.id) { voice in
                        row(ReviewSpeechChoice(mode: .voice, voiceID: voice.id), title: voice.name + " · " + voice.language, id: voice.id)
                    }
                }
            }
            .accessibilityIdentifier("speech-voices-list")
            .studyThemeSurface().navigationTitle(AppText.localized("読み上げ音声"))
            .safeAreaInset(edge: .bottom) {
                    TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                        Button(model.audio.isPlaying ? AppText.localized("試聴を停止") : AppText.localized("試聴"), systemImage: model.audio.isPlaying ? "stop.circle" : "play.circle") {
                            do {
                                if model.audio.isPlaying { model.audio.stop() }
                                else { try model.previewSpeechChoice(request, choice: choice) }
                            } catch { self.error = error.localizedDescription }
                        }.disabled(choice.mode == .off).accessibilityIdentifier("speech-preview")
                            .accessibilityValue(model.audio.isPlaying ? AppText.localized("再生中") : AppText.localized("停止中"))
                    }.padding().frame(maxWidth: .infinity).background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppText.localized("キャンセル")) { model.speechRequest = nil }.accessibilityIdentifier("speech-cancel") }
                ToolbarItem(placement: .confirmationAction) { Button(AppText.localized("適用")) {
                    do { try model.applySpeechChoice(request, choice: choice) } catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("speech-apply") }
            }
            .alert(AppText.localized("音声を設定できませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}
