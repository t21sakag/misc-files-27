import SwiftUI

struct DraftNotePreviewView: View {
    @ObservedObject var model: StudyModel
    let document: NoteDocument
    @Environment(\.dismiss) private var dismiss
    @State private var templates: [String] = []
    @State private var ordinals: [Int] = []
    @State private var ordinal = 0
    @State private var selected = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                ForEach(templates.indices, id: \.self) { index in
                    Button(templates[index]) { ordinal = ordinals[index]; selected = true }
                }
                if templates.isEmpty { Text("プレビューするカードテンプレートを読み込んでいます。") }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("カードのプレビュー")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
            .sheet(isPresented: $selected) { NoteTemplatePreviewView(model: model, typeID: document.typeID, ordinal: ordinal, document: document) }
            .task {
                do {
                    let schema = try await model.engine.noteType(document.typeID)
                    if (schema["config"] as? [String: Any])?["kind"] as? String == "KIND_CLOZE" {
                        var note = document.raw
                        note["fields"] = document.fields
                        let numbers = try await model.engine.call("NotesService.ClozeNumbersInNote", note)["numbers"] as? [Int] ?? []
                        let sorted = Array(Set(numbers.filter { $0 > 0 })).sorted()
                        ordinals = sorted.isEmpty ? [0] : sorted.map { $0 - 1 }
                        templates = ordinals.map { "穴埋め c\($0 + 1)" }
                    } else {
                        templates = (schema["templates"] as? [[String: Any]] ?? []).map { $0["name"] as? String ?? "カード" }
                        ordinals = Array(templates.indices)
                    }
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}
