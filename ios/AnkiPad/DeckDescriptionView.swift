import SwiftUI

struct DeckDescriptionRequest: Identifiable {
    let id = UUID()
    let deck: Deck
}
struct DeckDescriptionView: View {
    @ObservedObject var model: StudyModel
    let request: DeckDescriptionRequest
    @Environment(\.dismiss) private var dismiss
    @State private var raw: [String: Any] = [:]
    @State private var description = ""
    @State private var markdown = false
    @State private var editing = false
    @State private var html = ""
    @State private var typed = ""
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var discard = false
    var body: some View {
        NavigationStack {
            VStack {
                if !loaded { ProgressView() }
                else if editing {
                    Toggle("Markdownを使う", isOn: $markdown).padding(.horizontal)
                    TextEditor(text: $description).padding().font(.system(.body, design: .monospaced))
                } else if html.isEmpty { ContentUnavailableView("説明はありません", systemImage: "text.alignleft") }
                else {
                    ReviewerWebView(html: html, css: "", cardID: "deck-description", ordinal: 0, typing: nil, hideAudioButtons: true, typedAnswer: $typed, answer: false, media: model.engine.media,
                                    playTag: { _, _ in }, reveal: {}, scheduling: nil,
                                    schedulingRequest: { _, _ in throw EngineError(message: "説明では学習予定を変更できません。") }, schedulingError: { _ in })
                }
            }
            .navigationTitle(request.deck.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { if editing { discard = true } else { dismiss() } }.disabled(busy) }
                if !request.deck.filtered {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(editing ? "保存" : "編集") { if editing { save() } else { editing = true } }.disabled(!loaded || busy)
                    }
                }
            }
            .confirmationDialog("説明の変更を破棄しますか？", isPresented: $discard) { Button("破棄", role: .destructive) { dismiss() } }
            .interactiveDismissDisabled(editing || busy)
            .task {
                do {
                    raw = try await model.engine.call("DecksService.GetDeck", ["did": request.deck.id])
                    let normal = raw["normal"] as? [String: Any] ?? [:]
                    description = normal["description"] as? String ?? ""
                    markdown = normal["markdownDescription"] as? Bool ?? false
                    html = markdown ? try await model.engine.call("CardRenderingService.RenderMarkdown", ["markdown": description])["val"] as? String ?? "" : description
                    loaded = true
                } catch { self.error = error.localizedDescription }
            }
            .alert("説明を保存できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("閉じる", role: .cancel) { error = nil } } message: { Text(error ?? "") }
        }
    }
    private func save() {
        busy = true
        Task {
            defer { busy = false }
            do {
                var normal = raw["normal"] as? [String: Any] ?? [:]
                normal["description"] = description; normal["markdownDescription"] = markdown
                raw["normal"] = normal
                try await model.engine.backup()
                _ = try await model.engine.call("DecksService.UpdateDeck", raw)
                html = markdown ? try await model.engine.call("CardRenderingService.RenderMarkdown", ["markdown": description])["val"] as? String ?? "" : description
                editing = false
                model.refreshAfterEditing()
            } catch { self.error = error.localizedDescription }
        }
    }
}
