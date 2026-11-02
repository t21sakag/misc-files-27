import SwiftUI

struct BrowserSearchHistoryRequest: Identifiable {
    let id = UUID()
    let preferenceKey: String
    let profileID: String
}

struct BrowserSearchHistoryView: View {
    @Binding var entries: [String]
    let preferenceKey: String
    let select: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var clearing = false
    @State private var editMode: EditMode = .inactive
    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty { Text(AppText.localized("まだ検索履歴がありません。")) }
                ForEach(entries, id: \.self) { query in
                    Button { select(query); dismiss() } label: { Text(query).lineLimit(3) }
                        .accessibilityIdentifier("browser-history-query").accessibilityLabel(query)
                }.onDelete { offsets in
                    let removed = offsets.map { entries[$0] }
                    for query in removed { entries = BrowserSearchHistory.remove(query, key: preferenceKey) }
                }
            }
            .environment(\.editMode, $editMode)
            .accessibilityIdentifier("browser-history-list")
            .studyThemeSurface().navigationTitle(AppText.localized("最近の検索"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.localized("閉じる")) { dismiss() }.accessibilityIdentifier("browser-history-close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(AppText.localized("履歴を消去"), role: .destructive) { clearing = true }
                        .disabled(entries.isEmpty).accessibilityIdentifier("browser-history-clear")
                }
                ToolbarItem(placement: .secondaryAction) { EditButton().environment(\.editMode, $editMode).disabled(entries.isEmpty && editMode != .active) }
            }
            .confirmationDialog(AppText.localized("検索履歴をすべて消去しますか？"), isPresented: $clearing, titleVisibility: .visible) {
                Button(AppText.localized("履歴を消去"), role: .destructive) {
                    BrowserSearchHistory.clear(key: preferenceKey); entries = []; editMode = .inactive
                }.accessibilityIdentifier("browser-history-clear-confirm")
                Button(AppText.localized("キャンセル"), role: .cancel) {}
            }
        }
    }
}
