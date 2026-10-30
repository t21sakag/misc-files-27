import SwiftUI

struct FindReplaceRequest: Identifiable {
    let id = UUID()
    let noteIDs: [String]
}
struct FindReplaceView: View {
    @ObservedObject var model: StudyModel
    let request: FindReplaceRequest
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var replacement = ""
    @State private var onlySelected: Bool
    @State private var replacingTags = false
    @State private var regex = false
    @State private var matchCase = false
    @State private var field = ""
    @State private var fields: [String] = []
    @State private var confirming = false
    @State private var busy = false
    @State private var error: String?
    @State private var result: Int?
    init(model: StudyModel, request: FindReplaceRequest) {
        self.model = model; self.request = request
        _onlySelected = State(initialValue: !request.noteIDs.isEmpty)
    }
    private var scopeTitle: String {
        onlySelected ? AppText.localized("対象: \(request.noteIDs.count)ノート") : AppText.localized("対象: すべてのノート")
    }
    private var confirmationTitle: String {
        onlySelected ? AppText.localized("選択した\(request.noteIDs.count)ノートの内容を置換しますか？") : AppText.localized("すべてのノートを対象に置換しますか？")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(AppText.localized("選択したノートのみ"), isOn: $onlySelected)
                        .disabled(request.noteIDs.isEmpty).accessibilityIdentifier("replace-selected-only")
                    Toggle(AppText.localized("タグを置換"), isOn: $replacingTags).accessibilityIdentifier("replace-tags")
                    TextField(AppText.localized("検索する文字列"), text: $search).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("replace-search")
                    TextField(AppText.localized("置換後の文字列"), text: $replacement).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("replace-replacement")
                    if !replacingTags { Picker(AppText.localized("フィールド"), selection: $field) { Text(AppText.localized("すべてのフィールド")).tag(""); ForEach(fields, id: \.self) { Text($0).tag($0) } }.accessibilityIdentifier("replace-field") }
                    Toggle(AppText.localized("正規表現"), isOn: $regex)
                    Toggle(AppText.localized("大文字・小文字を区別"), isOn: $matchCase)
                } header: { Text(scopeTitle).accessibilityIdentifier("replace-scope") }
                if let result { Text(AppText.localized("\(result)件を変更しました。")).accessibilityIdentifier("replace-result") }
                if busy { ProgressView() }
            }
            .disabled(busy)
            .interactiveDismissDisabled(busy)
            .studyThemeSurface().navigationTitle(AppText.localized("検索と置換"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppText.localized("閉じる")) { dismiss() }.disabled(busy).accessibilityIdentifier("replace-close") }
                ToolbarItem(placement: .confirmationAction) { Button(AppText.localized("置換")) { confirming = true }.disabled(search.isEmpty || busy || (onlySelected && request.noteIDs.isEmpty)).accessibilityIdentifier("replace-submit") }
            }
            .confirmationDialog(confirmationTitle, isPresented: $confirming, titleVisibility: .visible) {
                Button(AppText.localized("置換する"), role: .destructive) { replace() }
            } message: { Text(AppText.localized("変更前のバックアップを保存します。正規表現ではAnkiの置換構文を使います。")) }
            .task {
                do {
                    let typeIDs = try await model.engine.noteTypes()
                    var names = Set<String>()
                    for type in typeIDs {
                        let schema = try await model.engine.noteType(type.id)
                        for item in schema["fields"] as? [[String: Any]] ?? [] { if let name = item["name"] as? String { names.insert(name) } }
                    }
                    fields = names.sorted()
                } catch { self.error = error.localizedDescription }
            }
            .alert(AppText.localized("置換できませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(AppText.localized("閉じる"), role: .cancel) { error = nil } } message: { Text(error ?? "") }
        }
    }
    private func replace() {
        guard !busy, !search.isEmpty, !onlySelected || !request.noteIDs.isEmpty else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await model.engine.backup()
                let noteIDs = onlySelected ? request.noteIDs : []
                let changes: [String: Any]
                if replacingTags {
                    changes = try await model.engine.call("TagsService.FindAndReplaceTag", ["noteIds": noteIDs, "search": search, "replacement": replacement, "regex": regex, "matchCase": matchCase])
                } else {
                    changes = try await model.engine.call("SearchService.FindAndReplace", ["nids": noteIDs, "search": search, "replacement": replacement, "regex": regex, "matchCase": matchCase, "fieldName": field])
                }
                result = changes["count"] as? Int ?? 0
                model.refreshAfterEditing()
            } catch { self.error = error.localizedDescription }
        }
    }
}
