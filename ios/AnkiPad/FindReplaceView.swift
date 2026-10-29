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
    @State private var regex = false
    @State private var matchCase = false
    @State private var field = ""
    @State private var fields: [String] = []
    @State private var confirming = false
    @State private var busy = false
    @State private var error: String?
    @State private var result: Int?
    var body: some View {
        NavigationStack {
            Form {
                Section(AppText.localized("対象: \(request.noteIDs.count)ノート")) {
                    TextField(AppText.localized("検索する文字列"), text: $search).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField(AppText.localized("置換後の文字列"), text: $replacement).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker(AppText.localized("フィールド"), selection: $field) { Text(AppText.localized("すべてのフィールド")).tag(""); ForEach(fields, id: \.self) { Text($0).tag($0) } }
                    Toggle(AppText.localized("正規表現"), isOn: $regex)
                    Toggle(AppText.localized("大文字・小文字を区別"), isOn: $matchCase)
                }
                if let result { Text(AppText.localized("\(result)件を変更しました。")) }
                if busy { ProgressView() }
            }
            .disabled(busy)
            .studyThemeSurface().navigationTitle(AppText.localized("検索と置換"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppText.localized("閉じる")) { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button(AppText.localized("置換")) { confirming = true }.disabled(search.isEmpty || busy) }
            }
            .confirmationDialog(AppText.localized("選択した\(request.noteIDs.count)ノートの内容を置換しますか？"), isPresented: $confirming, titleVisibility: .visible) {
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
        busy = true
        Task {
            defer { busy = false }
            do {
                try await model.engine.backup()
                let changes = try await model.engine.call("SearchService.FindAndReplace", ["nids": request.noteIDs, "search": search, "replacement": replacement, "regex": regex, "matchCase": matchCase, "fieldName": field])
                result = changes["count"] as? Int ?? 0
                model.refreshAfterEditing()
            } catch { self.error = error.localizedDescription }
        }
    }
}
