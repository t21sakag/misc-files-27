import SwiftUI

struct NoteTypeManagerView: View {
    @ObservedObject var model: StudyModel
    @Environment(\.dismiss) private var dismiss
    @State private var types: [NamedID] = []
    @State private var selected: NamedID?
    @State private var deleting: NamedID?
    @State private var adding = false
    @State private var naming = false
    @State private var copying: NamedID?
    @State private var name = ""
    @State private var kind = "KIND_BASIC"
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            List {
                ForEach(types) { type in
                    Button(type.name) { selected = type }.foregroundStyle(.primary)
                        .contextMenu {
                            Button("複製") { copying = type; name = type.name + " コピー"; naming = true }
                            Button("削除", role: .destructive) { deleting = type }
                        }
                }
                if busy { ProgressView() }
            }
            .studyThemeSurface().navigationTitle("ノートタイプ")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss(); model.refreshAfterEditing() } }
                ToolbarItem(placement: .primaryAction) { Button { name = ""; adding = true } label: { Image(systemName: "plus") }.disabled(busy).accessibilityIdentifier("notetype-add") }
            }
            .sheet(item: $selected, onDismiss: reload) { type in NoteTypeEditorView(model: model, type: type) }
            .sheet(isPresented: $adding) {
                NavigationStack {
                    Form {
                        TextField("名前", text: $name).accessibilityIdentifier("notetype-name")
                        Picker("種類", selection: $kind) {
                            Text("基本").tag("KIND_BASIC")
                            Text("基本（裏表）").tag("KIND_BASIC_AND_REVERSED")
                            Text("基本（裏表を任意に選択）").tag("KIND_BASIC_OPTIONAL_REVERSED")
                            Text("基本（解答を入力）").tag("KIND_BASIC_TYPING")
                            Text("穴埋め").tag("KIND_CLOZE")
                            Text("画像穴埋め").tag("KIND_IMAGE_OCCLUSION")
                        }
                    }.studyThemeSurface().navigationTitle("ノートタイプを追加")
                    .alert("作成できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                        Button("閉じる", role: .cancel) { error = nil }
                    } message: { Text(error ?? "") }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { adding = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("追加") {
                            run { try await model.engine.addStockNoteType(name: name, kind: kind); adding = false; types = try await model.engine.noteTypes() }
                        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy).accessibilityIdentifier("notetype-create") }
                    }
                }
            }
            .alert("ノートタイプを複製", isPresented: $naming) {
                TextField("名前", text: $name)
                if let copying { Button("複製") { run { try await model.engine.copyNoteType(copying.id, name: name); types = try await model.engine.noteTypes() } } }
                Button("キャンセル", role: .cancel) {}
            }
            .confirmationDialog("ノートタイプと関連するすべてのノートを削除しますか？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                if let type = deleting { Button("削除", role: .destructive) { run { try await model.engine.deleteNoteType(type.id); deleting = nil; types = try await model.engine.noteTypes() } } }
            }
            .alert("処理できませんでした", isPresented: Binding(get: { error != nil && !adding }, set: { if !$0 { error = nil } })) {
                Button("閉じる", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
            .task { reload() }
        }
    }
    private func reload() { run { types = try await model.engine.noteTypes() } }
    private func run(_ operation: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task { defer { busy = false }; do { try await operation() } catch { self.error = error.localizedDescription } }
    }
}

struct NoteTypeEditorView: View {
    @ObservedObject var model: StudyModel
    let type: NamedID
    @Environment(\.dismiss) private var dismiss
    @State private var schema: [String: Any] = [:]
    @State private var loaded = false
    @State private var busy = false
    @State private var dirty = false
    @State private var discarding = false
    @State private var addingField = false
    @State private var fieldName = ""
    @State private var error: String?
    private var fields: [[String: Any]] { schema["fields"] as? [[String: Any]] ?? [] }
    private var templates: [[String: Any]] { schema["templates"] as? [[String: Any]] ?? [] }
    private var cloze: Bool { (schema["config"] as? [String: Any])?["kind"] as? String == "KIND_CLOZE" }
    var body: some View {
        NavigationStack {
            Form {
                if loaded {
                    Section("名前") { TextField("名前", text: text("name")).accessibilityIdentifier("notetype-edit-name") }
                    Section {
                        ForEach(fields.indices, id: \.self) { index in
                            NavigationLink(fields[index]["name"] as? String ?? "フィールド") { NoteFieldEditor(value: element("fields", index)) }
                        }
                        .onMove { source, destination in var result = fields; result.move(fromOffsets: source, toOffset: destination); schema["fields"] = result; dirty = true }
                        .onDelete { offsets in
                            if offsets.contains(where: { ((fields[$0]["config"] as? [String: Any])?["preventDeletion"] as? Bool) == true }) { error = "削除から保護されたフィールドがあります。"; return }
                            var result = fields; result.remove(atOffsets: offsets); schema["fields"] = result; dirty = true
                        }
                        Button("フィールドを追加") { fieldName = ""; addingField = true }
                    } header: { Text("フィールド") } footer: { Text("削除して保存すると、すべての関連ノートからそのフィールドの値が削除されます。保存前にバックアップを作成します。") }
                    Section("カードテンプレート") {
                        ForEach(templates.indices, id: \.self) { index in
                            NavigationLink(templates[index]["name"] as? String ?? "カード") {
                                NoteTemplateEditor(model: model, schema: Binding(get: { schema }, set: { schema = $0; dirty = true }), ordinal: index, saved: { dirty = false })
                            }
                        }
                        .onMove { source, destination in var result = templates; result.move(fromOffsets: source, toOffset: destination); schema["templates"] = result; dirty = true }
                        .onDelete { offsets in var result = templates; result.remove(atOffsets: offsets); schema["templates"] = result; dirty = true }
                        if !cloze {
                            Button("テンプレートを追加") {
                                var template = templates.first ?? [:]
                                template.removeValue(forKey: "ord")
                                template["name"] = "カード \(templates.count + 1)"
                                schema["templates"] = templates + [template]
                                dirty = true
                            }
                        }
                    }
                    Section("スタイル（CSS）") {
                        TextEditor(text: configText("css")).font(.system(.body, design: .monospaced)).frame(minHeight: 180)
                    }
                    Section("並べ替えに使うフィールド") {
                        Picker("フィールド", selection: sortField) {
                            ForEach(fields.indices, id: \.self) { index in Text(fields[index]["name"] as? String ?? "").tag(index) }
                        }
                    }
                } else { ProgressView() }
            }
            .disabled(busy)
            .studyThemeSurface().navigationTitle("ノートタイプを編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { if dirty { discarding = true } else { dismiss() } } }
                ToolbarItemGroup(placement: .confirmationAction) {
                    EditButton()
                    Button("保存") { save() }.disabled(!loaded || busy || fields.isEmpty || templates.isEmpty).accessibilityIdentifier("notetype-save")
                }
            }
            .interactiveDismissDisabled(dirty || busy)
            .confirmationDialog("変更を破棄しますか？", isPresented: $discarding) { Button("破棄", role: .destructive) { dismiss() } }
            .alert("フィールドを追加", isPresented: $addingField) {
                TextField("フィールド名", text: $fieldName)
                Button("追加") {
                    var result = fields
                    result.append(["name": fieldName, "config": ["fontName": "Arial", "fontSize": 20]])
                    schema["fields"] = result; dirty = true
                }.disabled(fieldName.isEmpty)
                Button("キャンセル", role: .cancel) {}
            }
            .alert("保存できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
            .task { do { schema = try await model.engine.noteType(type.id); loaded = true } catch { self.error = error.localizedDescription } }
        }
    }
    private func save() {
        busy = true
        Task {
            defer { busy = false }
            do { try await model.engine.saveNoteType(schema); dirty = false; model.refreshAfterEditing(); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
    private func text(_ key: String) -> Binding<String> { Binding(get: { schema[key] as? String ?? "" }, set: { schema[key] = $0; dirty = true }) }
    private func configText(_ key: String) -> Binding<String> {
        Binding(get: { (schema["config"] as? [String: Any])?[key] as? String ?? "" }, set: { value in var config = schema["config"] as? [String: Any] ?? [:]; config[key] = value; schema["config"] = config; dirty = true })
    }
    private var sortField: Binding<Int> {
        Binding(get: { (schema["config"] as? [String: Any])?["sortFieldIdx"] as? Int ?? 0 }, set: { value in var config = schema["config"] as? [String: Any] ?? [:]; config["sortFieldIdx"] = value; schema["config"] = config; dirty = true })
    }
    private func element(_ key: String, _ index: Int) -> Binding<[String: Any]> {
        Binding(get: { (schema[key] as? [[String: Any]] ?? [])[index] }, set: { value in var array = schema[key] as? [[String: Any]] ?? []; guard array.indices.contains(index) else { return }; array[index] = value; schema[key] = array; dirty = true })
    }
}

struct NoteFieldEditor: View {
    @Binding var value: [String: Any]
    var body: some View {
        Form {
            TextField("フィールド名", text: text("name", config: false))
            TextField("編集画面のフォント", text: text("fontName"))
            Stepper("編集画面の文字サイズ: \(size.wrappedValue)", value: size, in: 8...100)
            Toggle("右から左に入力", isOn: boolean("rtl"))
            Toggle("追加時に値を保持", isOn: boolean("sticky"))
            Toggle("プレーンテキスト", isOn: boolean("plainText"))
            Toggle("初期状態で折りたたむ", isOn: boolean("collapsed"))
            Toggle("検索対象から除外", isOn: boolean("excludeFromSearch"))
            Toggle("削除から保護", isOn: boolean("preventDeletion"))
            TextField("説明", text: text("description"), axis: .vertical)
        }.studyThemeSurface().navigationTitle("フィールド")
    }
    private func text(_ key: String, config: Bool = true) -> Binding<String> {
        Binding(get: { (config ? value["config"] as? [String: Any] ?? [:] : value)[key] as? String ?? "" }, set: { updated in
            if config { var data = value["config"] as? [String: Any] ?? [:]; data[key] = updated; value["config"] = data }
            else { value[key] = updated }
        })
    }
    private func boolean(_ key: String) -> Binding<Bool> {
        Binding(get: { (value["config"] as? [String: Any])?[key] as? Bool ?? false }, set: { updated in var data = value["config"] as? [String: Any] ?? [:]; data[key] = updated; value["config"] = data })
    }
    private var size: Binding<Int> {
        Binding(get: { (value["config"] as? [String: Any])?["fontSize"] as? Int ?? 20 }, set: { updated in var data = value["config"] as? [String: Any] ?? [:]; data["fontSize"] = updated; value["config"] = data })
    }
}
