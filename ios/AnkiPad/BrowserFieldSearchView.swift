import SwiftUI

extension Engine {
    func browserFieldSearch(_ request: BrowserFieldSearchRequest) throws -> String {
        try request.build { try call("SearchService.BuildSearchString", $0) }
    }
}

@MainActor struct BrowserFieldSearchView: View {
    @ObservedObject var model: StudyModel
    let currentSearch: String
    let apply: (String) -> Void
    private let engine: Engine
    private let profileID: String
    @Environment(\.dismiss) private var dismiss
    @State private var field = ""
    @State private var fields: [String] = []
    @State private var mode = BrowserFieldSearchMode.contains
    @State private var text = ""
    @State private var combine = false
    @State private var busy = true
    @State private var active = true
    @State private var error: String?

    init(model: StudyModel, currentSearch: String, apply: @escaping (String) -> Void) {
        self.model = model; self.currentSearch = currentSearch; self.apply = apply
        engine = model.engine; profileID = model.currentProfile.id
    }
    private func title(_ mode: BrowserFieldSearchMode) -> String {
        switch mode {
        case .contains: return AppText.localized("文字列を含む")
        case .exact: return AppText.localized("完全一致")
        case .empty: return AppText.localized("空のフィールド")
        case .nonEmpty: return AppText.localized("空でないフィールド")
        case .exists: return AppText.localized("フィールドの存在")
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker(AppText.localized("フィールド"), selection: $field) {
                    ForEach(fields, id: \.self) { Text($0).tag($0) }
                }.accessibilityIdentifier("field-search-name")
                Picker(AppText.localized("検索方法"), selection: $mode) {
                    ForEach(BrowserFieldSearchMode.allCases, id: \.self) { Text(title($0)).tag($0) }
                }.accessibilityIdentifier("field-search-mode")
                if mode.needsText {
                    TextField(AppText.localized("検索文字列"), text: $text)
                        .accessibilityIdentifier("field-search-text")
                }
                if !currentSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Toggle(AppText.localized("現在の検索条件と組み合わせる"), isOn: $combine)
                        .accessibilityIdentifier("field-search-combine")
                    Text(currentSearch).font(.footnote).foregroundStyle(.secondary)
                }
                if !busy && fields.isEmpty { Text(AppText.localized("検索できるフィールドがありません。")) }
            }
            .disabled(busy)
            .studyThemeSurface().navigationTitle(AppText.localized("フィールドを検索"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.localized("キャンセル")) { active = false; dismiss() }
                        .accessibilityIdentifier("field-search-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppText.localized("検索")) { submit() }
                        .disabled(busy || field.isEmpty || (mode.needsText && text.isEmpty))
                        .accessibilityIdentifier("field-search-apply")
                }
            }
            .task {
                do {
                    var names = Set<String>()
                    for type in try await engine.noteTypes() {
                        let schema = try await engine.noteType(type.id)
                        for item in schema["fields"] as? [[String: Any]] ?? [] {
                            if let name = item["name"] as? String { names.insert(name) }
                        }
                    }
                    guard !Task.isCancelled, active else { return }
                    fields = names.sorted(); field = fields.first ?? ""; busy = false
                } catch { if active { self.error = error.localizedDescription; busy = false } }
            }
            .onDisappear { active = false }
            .alert(AppText.localized("検索できませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
    private func submit() {
        let request = BrowserFieldSearchRequest(fieldName: field, mode: mode, text: text,
                                               currentSearch: currentSearch, combineWithCurrent: combine)
        busy = true
        Task {
            defer { busy = false }
            do {
                let query = try await engine.browserFieldSearch(request)
                guard active else { return }
                guard model.currentProfile.id == profileID else {
                    error = AppText.localized("プロファイルが変わりました。検索画面を開き直してください。")
                    return
                }
                apply(query); dismiss()
            } catch { if active { self.error = AppText.localized("検索条件を作成できませんでした。") } }
        }
    }
}
