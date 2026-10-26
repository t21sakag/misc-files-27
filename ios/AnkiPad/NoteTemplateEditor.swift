import SwiftUI

struct NoteTemplateEditor: View {
    @ObservedObject var model: StudyModel
    @Binding var schema: [String: Any]
    let ordinal: Int
    let saved: () -> Void
    @State private var preview = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var activeTemplate: String?
    @State private var restoreBrowser = false
    private var template: [String: Any] { (schema["templates"] as? [[String: Any]] ?? [])[ordinal] }
    var body: some View {
        Form {
            Section("名前") { TextField("カード名", text: text("name", config: false)) }
            Section("表面のテンプレート") { TextEditor(text: text("qFormat")).focused($activeTemplate, equals: "qFormat").font(.system(.body, design: .monospaced)).frame(minHeight: 200) }
            Section("裏面のテンプレート") { TextEditor(text: text("aFormat")).focused($activeTemplate, equals: "aFormat").font(.system(.body, design: .monospaced)).frame(minHeight: 200) }
            Section("デッキの上書き") {
                Picker("生成するカードのデッキ", selection: text("targetDeckId", fallback: "0")) {
                    Text("指定なし").tag("0")
                    ForEach(model.decks) { Text($0.name).tag($0.id) }
                }
            }
            DisclosureGroup("ブラウザー表示のテンプレート") {
                Text("表面").font(.caption)
                TextEditor(text: text("qFormatBrowser")).focused($activeTemplate, equals: "qFormatBrowser").font(.system(.body, design: .monospaced)).frame(minHeight: 100)
                Text("裏面").font(.caption)
                TextEditor(text: text("aFormatBrowser")).focused($activeTemplate, equals: "aFormatBrowser").font(.system(.body, design: .monospaced)).frame(minHeight: 100)
            }
            Section {
                Menu("フィールドを挿入", systemImage: "text.badge.plus") {
                    ForEach((schema["fields"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }, id: \.self) { name in
                        Menu(name) {
                            Button("通常") { insert("{{" + name + "}}") }
                            Button("穴埋め") { insert("{{cloze:" + name + "}}") }
                            Button("解答を入力") { insert("{{type:" + name + "}}") }
                        }
                    }
                    Button("表面の内容（FrontSide）") { insert("{{FrontSide}}") }
                }
                Button("Markdownとしてコピー", systemImage: "doc.on.doc") {
                    let config = template["config"] as? [String: Any] ?? [:]
                    let css = (schema["config"] as? [String: Any])?["css"] as? String ?? ""
                    UIPasteboard.general.string = "## Front\n```html\n" + (config["qFormat"] as? String ?? "") + "\n```\n## Back\n```html\n" + (config["aFormat"] as? String ?? "") + "\n```\n## Styling\n```css\n" + css + "\n```"
                }
                Button("ブラウザー表示を既定に戻す") { restoreBrowser = true }
                Button("保存してプレビュー") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            try await model.engine.saveNoteType(schema)
                            schema = try await model.engine.noteType(schema["id"] as? String ?? "0")
                            saved()
                            preview = true
                        } catch { self.error = error.localizedDescription }
                    }
                }.disabled(busy)
                Text("{{フィールド名}}、{{FrontSide}}、{{cloze:フィールド名}}、{{type:フィールド名}} などのAnkiテンプレートを使えます。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .disabled(busy)
        .navigationTitle("カードテンプレート")
        .confirmationDialog("ブラウザー表示のテンプレートをリセットしますか？", isPresented: $restoreBrowser) {
            Button("既定に戻す", role: .destructive) { text("qFormatBrowser").wrappedValue = ""; text("aFormatBrowser").wrappedValue = "" }
        }
        .sheet(isPresented: $preview) { NoteTemplatePreviewView(model: model, typeID: schema["id"] as? String ?? "0", ordinal: ordinal) }
        .alert("保存できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("閉じる", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
    private func insert(_ value: String) {
        let key = activeTemplate ?? "qFormat"
        let target = text(key)
        target.wrappedValue += value
    }
    private func text(_ key: String, config: Bool = true, fallback: String = "") -> Binding<String> {
        Binding(get: { (config ? template["config"] as? [String: Any] ?? [:] : template)[key] as? String ?? fallback }, set: { updated in
            var array = schema["templates"] as? [[String: Any]] ?? []
            guard array.indices.contains(ordinal) else { return }
            if config { var data = array[ordinal]["config"] as? [String: Any] ?? [:]; data[key] = updated; array[ordinal]["config"] = data }
            else { array[ordinal][key] = updated }
            schema["templates"] = array
        })
    }
}

struct NoteTemplatePreviewView: View {
    @ObservedObject var model: StudyModel
    let typeID: String
    let ordinal: Int
    var document: NoteDocument? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var rendered: TemplatePreview?
    @State private var answer = false
    @State private var error: String?
    @State private var typed = ""
    @State private var audio = CardAudio()
    var body: some View {
        NavigationStack {
            VStack {
                if let rendered {
                    Picker("表示する面", selection: $answer) { Text("表面").tag(false); Text("裏面").tag(true) }.pickerStyle(.segmented).padding()
                    ReviewerWebView(html: TypedAnswerMarkup.replace(in: answer ? rendered.answer : rendered.question, with: "<span id=typeans>........</span>"), css: rendered.css,
                        cardID: "preview", ordinal: ordinal, typing: nil, hideAudioButtons: false, typedAnswer: $typed, answer: answer, media: model.engine.media,
                        playTag: { isAnswer, index in
                            let tags = isAnswer ? rendered.answerAV : rendered.questionAV
                            if tags.indices.contains(index) { audio.play([tags[index]], media: model.engine.media) }
                        }, reveal: { answer = true }, scheduling: nil,
                        schedulingRequest: { _, _ in throw EngineError(message: "プレビューではスケジュールを変更できません。") }, schedulingError: { _ in })
                } else if let error { Text(error).padding() }
                else { ProgressView() }
            }
            .navigationTitle("プレビュー")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { audio.stop(); dismiss() } } }
            .onDisappear { audio.stop() }
            .task { do { rendered = try await model.engine.templatePreview(typeID: typeID, ordinal: ordinal, document: document) } catch { self.error = error.localizedDescription } }
        }
    }
}
