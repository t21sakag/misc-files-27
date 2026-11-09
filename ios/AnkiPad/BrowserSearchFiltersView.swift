import SwiftUI

/// Edit one owned request. Draft changes are isolated until the real engine
/// has resolved every selected identity and built the complete search.
@MainActor struct BrowserSearchFiltersView: View {
    @ObservedObject var model: StudyModel
    @State private var request: BrowserSearchRequest
    private let decks: [Deck]
    private let tags: [String]
    private let noteTypes: [NamedID]
    private let flagNames: [String]
    private let engine: Engine
    private let profileID: String
    private let apply: (BrowserSearchRequest, String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var active = true
    @State private var error: String?

    init(model: StudyModel, request: BrowserSearchRequest, tags: [String], noteTypes: [NamedID],
         apply: @escaping (BrowserSearchRequest, String) throws -> Void) {
        self.model = model; _request = State(initialValue: request)
        decks = model.decks; self.tags = tags; self.noteTypes = noteTypes
        flagNames = (0..<8).map { model.flagLabels.name($0) }
        engine = model.engine; profileID = model.currentProfile.id; self.apply = apply
    }

    private func selection<Value: Equatable>(_ key: WritableKeyPath<BrowserSearchRequest, [Value]>, _ value: Value) -> Binding<Bool> {
        Binding(get: { request[keyPath: key].contains(value) }, set: { selected in
            var values = request[keyPath: key]
            if selected { if !values.contains(value) { values.append(value) } }
            else { values.removeAll { $0 == value } }
            request[keyPath: key] = values
        })
    }
    private func title(_ state: BrowserSearchCardState) -> String {
        switch state {
        case .new: return AppText.localized("新規")
        case .learning: return AppText.localized("学習中")
        case .review: return AppText.localized("復習")
        case .buried: return AppText.localized("今日非表示")
        case .suspended: return AppText.localized("保留")
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(AppText.localized("検索条件")) {
                    TextField(AppText.localized("検索条件"), text: $request.query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("search-filters-query")
                    Text(AppText.localized("同じ項目ではいずれかに一致し、異なる項目はすべてに一致するカードを検索します。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(AppText.localized("デッキ")) {
                    ForEach(decks) { deck in
                        Toggle(deck.name, isOn: selection(\.deckIDs, deck.id))
                            .accessibilityIdentifier("search-filters-deck-\(deck.id)")
                    }
                }
                Section(AppText.localized("フラグ")) {
                    ForEach(BrowserSearchFlag.allCases, id: \.rawValue) { flag in
                        Toggle(flagNames[flag.rawValue], isOn: selection(\.flags, flag))
                            .accessibilityIdentifier("search-filters-flag-\(flag.rawValue)")
                    }
                }
                Section(AppText.localized("タグ")) {
                    ForEach(tags, id: \.self) { tag in
                        Toggle(tag, isOn: selection(\.tags, tag)).accessibilityIdentifier("search-filters-tag-\(tag)")
                    }
                }
                Section(AppText.localized("ノートタイプ")) {
                    ForEach(noteTypes) { type in
                        Toggle(type.name, isOn: selection(\.noteTypeIDs, type.id))
                            .accessibilityIdentifier("search-filters-type-\(type.id)")
                    }
                }
                Section(AppText.localized("状態")) {
                    ForEach(BrowserSearchCardState.allCases, id: \.rawValue) { state in
                        Toggle(title(state), isOn: selection(\.cardStates, state))
                            .accessibilityIdentifier("search-filters-state-\(state.rawValue)")
                    }
                }
                Section {
                    Button(AppText.localized("絞り込みを解除")) { request = BrowserSearchRequest(query: request.query) }
                        .disabled(!request.hasFilters).accessibilityIdentifier("search-filters-clear")
                }
                if busy { ProgressView() }
            }
            .accessibilityIdentifier("search-filters-form")
            #if DEBUG
            .overlay(alignment: .bottomLeading) {
                if UITestIsolation.namespace() != nil,
                   ProcessInfo.processInfo.arguments.contains("--uitest-browser-input-trace") {
                    BrowserInputDiagnosticsView(readValue: {
                        BrowserInputDiagnostics.read(loaded: true, busy: busy, notes: false)
                            + "\nmodel_flags=\(request.flags.map(\.rawValue));model_states=\(request.cardStates.map(\.rawValue));query_empty=\(request.query.isEmpty)"
                            + "\nmodel_decks=\(request.deckIDs);model_note_types=\(request.noteTypeIDs)"
                    }).fixedSize().accessibilityIdentifier("browser-native-input-state").allowsHitTesting(false)
                }
            }
            #endif
            .disabled(busy).studyThemeSurface().navigationTitle(AppText.localized("検索条件"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.localized("キャンセル")) { active = false; dismiss() }
                        .disabled(busy).accessibilityIdentifier("search-filters-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppText.localized("適用")) { submit() }
                        .disabled(busy).accessibilityIdentifier("search-filters-apply")
                }
            }
            .interactiveDismissDisabled(busy).onDisappear { active = false }
            .alert(AppText.localized("検索できませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
    private func submit() {
        guard !busy, active else { return }
        busy = true
        let snapshot = request
        Task {
            defer { busy = false }
            do {
                let query = try await engine.browserSearchQuery(snapshot)
                guard active else { return }
                guard model.currentProfile.id == profileID else {
                    throw EngineError(message: AppText.localized("プロファイルが変わりました。検索画面を開き直してください。"))
                }
                try apply(snapshot, query); active = false; dismiss()
            } catch { if active { self.error = error.localizedDescription } }
        }
    }
}
