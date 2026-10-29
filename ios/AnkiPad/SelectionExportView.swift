import SwiftUI

struct SelectionExportRequest: Identifiable {
    let id = UUID()
    let cardIDs: [String]
}
struct SelectionExportView: View {
    @ObservedObject var model: StudyModel
    let request: SelectionExportRequest
    @Environment(\.dismiss) private var dismiss
    @State private var format = "apkg"
    @State private var scheduling = true
    @State private var media = true
    @State private var deckConfigs = true
    @State private var legacy = false
    @State private var html = true
    @State private var tags = true
    @State private var deck = true
    @State private var notetype = true
    @State private var guid = false
    @State private var busy = false
    @State private var exported: URL?
    @State private var share = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section(AppText.localized("対象: \(request.cardIDs.count)枚")) {
                    Picker(AppText.localized("形式"), selection: $format) {
                        Text(AppText.localized("Ankiデッキパッケージ (.apkg)")).tag("apkg")
                        Text(AppText.localized("ノートのテキスト")).tag("notes")
                        Text(AppText.localized("カードのテキスト")).tag("cards")
                    }
                    if format == "apkg" {
                        Toggle(AppText.localized("学習履歴を含める"), isOn: $scheduling)
                        Toggle(AppText.localized("メディアを含める"), isOn: $media)
                        Toggle(AppText.localized("デッキ設定を含める"), isOn: $deckConfigs)
                        Toggle(AppText.localized("古いAnkiとの互換性"), isOn: $legacy)
                    } else {
                        Toggle(AppText.localized("HTMLを含める"), isOn: $html)
                        if format == "notes" {
                            Toggle(AppText.localized("タグを含める"), isOn: $tags); Toggle(AppText.localized("デッキ名を含める"), isOn: $deck)
                            Toggle(AppText.localized("ノートタイプを含める"), isOn: $notetype); Toggle(AppText.localized("一意の識別子を含める"), isOn: $guid)
                        }
                    }
                }
                if busy { ProgressView(AppText.localized("書き出し中…")) }
            }
            .disabled(busy)
            .studyThemeSurface().navigationTitle(AppText.localized("選択したカードを書き出す"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppText.localized("閉じる")) { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button(AppText.localized("書き出す")) { export() }.disabled(busy || request.cardIDs.isEmpty) }
            }
            .sheet(isPresented: $share) { if let exported { ShareSheet(url: exported) } }
            .alert(AppText.localized("書き出せませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(AppText.localized("閉じる"), role: .cancel) { error = nil } } message: { Text(error ?? "") }
        }
    }
    private func export() {
        busy = true
        Task {
            defer { busy = false }
            do {
                let path = FileManager.default.temporaryDirectory.appendingPathComponent("AnkiPad-selected-" + UUID().uuidString + (format == "apkg" ? ".apkg" : ".txt"))
                let limit: [String: Any] = ["cardIds": ["cids": request.cardIDs]]
                if format == "apkg" {
                    _ = try await model.engine.call("ImportExportService.ExportAnkiPackage", ["outPath": path.path, "options": ["withScheduling": scheduling, "withMedia": media, "withDeckConfigs": deckConfigs, "legacy": legacy], "limit": limit])
                } else if format == "cards" {
                    _ = try await model.engine.call("ImportExportService.ExportCardCsv", ["outPath": path.path, "withHtml": html, "limit": limit])
                } else {
                    _ = try await model.engine.call("ImportExportService.ExportNoteCsv", ["outPath": path.path, "withHtml": html, "withTags": tags, "withDeck": deck, "withNotetype": notetype, "withGuid": guid, "limit": limit])
                }
                exported = path; share = true
            } catch { self.error = error.localizedDescription }
        }
    }
}
