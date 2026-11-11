import SwiftUI

private struct DeckCreationPrompt: Identifiable {
    let id = UUID()
    let parentID: String?
    let parentName: String?
}

@MainActor struct DeckSelectionView: View {
    @ObservedObject var model: StudyModel
    let currentID: String?
    let noneLabel: String?
    let selected: (String?) -> Void
    private let engine: Engine
    private let profileID: String
    @Environment(\.dismiss) private var dismiss
    @State private var decks: [Deck] = []
    @State private var search = ""
    @State private var collapsed: Set<String> = []
    @State private var loaded = false
    @State private var busy = false
    @State private var active = true
    @State private var prompt: DeckCreationPrompt?
    @State private var createdID: String?
    @State private var error: String?

    init(model: StudyModel, currentID: String?, noneLabel: String? = nil,
         engine expectedEngine: Engine? = nil, profileID expectedProfileID: String? = nil,
         selected: @escaping (String?) -> Void) {
        self.model = model; self.currentID = currentID; self.noneLabel = noneLabel; self.selected = selected
        engine = expectedEngine ?? model.engine; profileID = expectedProfileID ?? model.currentProfileID
    }
    private var choices: [Deck] { DeckSelectionChoices.visible(decks, query: search, collapsed: collapsed) }
    var body: some View {
        NavigationStack {
            List {
                if !loaded { ProgressView() }
                else {
                    if let noneLabel {
                        Button { choose(nil) } label: {
                            HStack { Text(noneLabel); Spacer(); if currentID == nil { Image(systemName: "checkmark") } }
                        }.accessibilityIdentifier("deck-picker-none")
                    }
                    ForEach(choices) { deck in
                        HStack {
                            if deck.hasChildren {
                                Button {
                                    if !collapsed.insert(deck.id).inserted { collapsed.remove(deck.id) }
                                } label: {
                                    Image(systemName: collapsed.contains(deck.id) ? "chevron.right" : "chevron.down")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(collapsed.contains(deck.id) ? AppText.localized("展開") : AppText.localized("折りたたむ"))
                                .accessibilityIdentifier("deck-picker-expand-" + deck.id)
                            }
                            Button { choose(deck.id) } label: {
                                HStack {
                                    Text(deck.fullName).multilineTextAlignment(.leading)
                                    Spacer()
                                    if deck.id == currentID { Image(systemName: "checkmark") }
                                }.frame(maxWidth: .infinity).contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("deck-picker-choice-" + deck.id)
                            .contextMenu {
                                Button(AppText.localized("サブデッキを作成")) { prompt = DeckCreationPrompt(parentID: deck.id, parentName: deck.fullName) }
                                    .accessibilityIdentifier("deck-picker-add-child")
                            }
                        }.padding(.leading, CGFloat(deck.level) * 12)
                    }
                    if choices.isEmpty { Text(AppText.localized("該当するデッキがありません")) }
                }
            }
            .accessibilityIdentifier("deck-picker-list")
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: AppText.localized("デッキを検索"))
            .onChange(of: search) { _, value in
                // Search expands its matching nodes locally, never in the collection.
                let matching = DeckSelectionChoices.visible(decks, query: value, collapsed: [])
                if !value.isEmpty { collapsed.subtract(matching.map(\.id)) }
            }
            .disabled(busy || model.busy)
            .studyThemeSurface().navigationTitle(AppText.localized("デッキを選択"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.localized("キャンセル")) { active = false; dismiss() }
                        .disabled(busy).accessibilityIdentifier("deck-picker-cancel")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { prompt = DeckCreationPrompt(parentID: nil, parentName: nil) } label: { Image(systemName: "plus") }
                        .disabled(!loaded || busy || model.busy)
                        .accessibilityLabel(AppText.localized("デッキを作成")).accessibilityIdentifier("deck-picker-add")
                }
            }
            .sheet(item: $prompt, onDismiss: finishCreatedDeck) { request in
                DeckCreationForm(parentName: request.parentName) { name in
                    try await create(name, parentID: request.parentID)
                }
            }
            .alert(AppText.localized("デッキを選択できませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) {}
            } message: { Text(error ?? "") }
            .interactiveDismissDisabled(busy).onDisappear { active = false }
            .task {
                do {
                    try requireCurrentProfile()
                    let current = try await engine.decks()
                    try requireCurrentProfile()
                    decks = current; collapsed = Set(current.filter(\.collapsed).map(\.id)); loaded = true
                } catch { self.error = error.localizedDescription }
            }
        }
    }
    private func requireCurrentProfile() throws {
        guard active, model.profilesReady, model.currentProfileID == profileID, model.engine === engine else {
            throw EngineError(message: AppText.localized("プロファイルが変わりました。画面を開き直してください。"))
        }
    }
    private func choose(_ id: String?) {
        guard !busy, !model.busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try requireCurrentProfile()
                if let id {
                    let deck = try await engine.call("DecksService.GetDeck", ["did": id])
                    guard deck["filtered"] == nil else {
                        throw EngineError(message: AppText.localized("フィルターデッキは選択できません。"))
                    }
                } else if noneLabel == nil { return }
                try requireCurrentProfile()
                selected(id); active = false; dismiss()
            } catch { if active { self.error = error.localizedDescription } }
        }
    }
    private func create(_ submitted: String, parentID: String?) async throws {
        guard !busy, !model.busy else {
            throw EngineError(message: AppText.localized("処理が終わってからもう一度選んでください。"))
        }
        busy = true
        defer { busy = false }
        try requireCurrentProfile()
        let id = try await engine.createDeckForSelection(submitted, parentID: parentID)
        let current = try await engine.decks()
        try requireCurrentProfile()
        decks = current; model.decks = current; createdID = id
    }
    private func finishCreatedDeck() {
        guard let id = createdID else { return }
        createdID = nil
        do {
            try requireCurrentProfile()
            selected(id); active = false; dismiss()
        } catch { if active { self.error = error.localizedDescription } }
    }
}

@MainActor private struct DeckCreationForm: View {
    let parentName: String?
    let create: (String) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if let parentName { LabeledContent(AppText.localized("デッキ"), value: parentName) }
                TextField(AppText.localized("名前"), text: $name).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("deck-picker-name").submitLabel(.done).onSubmit(submit)
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("deck-picker-create-error") }
                if busy { ProgressView() }
            }
            .disabled(busy).accessibilityIdentifier("deck-picker-create-form")
            .studyThemeSurface().navigationTitle(AppText.localized("デッキを作成"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.localized("キャンセル")) { dismiss() }.disabled(busy).accessibilityIdentifier("deck-picker-create-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppText.localized("作成"), action: submit)
                        .disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("deck-picker-create-confirm")
                }
            }
            .interactiveDismissDisabled(busy)
        }
    }
    private func submit() {
        guard !busy, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let submitted = name
        busy = true; error = nil
        Task {
            defer { busy = false }
            do { try await create(submitted); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}
