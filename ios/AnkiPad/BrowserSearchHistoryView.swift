import SwiftUI

struct BrowserSearchHistoryRequest: Identifiable {
    let id = UUID()
    let preferenceKey: String
    let profileID: String
    let engine: Engine
}

@MainActor struct BrowserSearchHistoryView: View {
    @Binding var entries: [BrowserSearchRequest]
    let preferenceKey: String
    let resolve: (BrowserSearchRequest) async throws -> String
    let select: (BrowserSearchRequest, String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var clearing = false
    @State private var editMode: EditMode = .inactive
    @State private var titles: [BrowserSearchRequest: String] = [:]
    @State private var loading = true
    @State private var submitting = false
    @State private var active = true
    @State private var error: String?
    private func title(_ entry: BrowserSearchRequest) -> String {
        titles[entry] ?? (entry.query.isEmpty ? AppText.localized("この検索条件を読み込めませんでした。") : entry.query)
    }
    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty { Text(AppText.localized("まだ検索履歴がありません。")) }
                ForEach(Array(entries.enumerated()), id: \.element) { index, entry in
                    Button { choose(entry) } label: {
                        VStack(alignment: .leading) {
                            Text(title(entry)).lineLimit(3)
                            if !loading && titles[entry] == nil {
                                Text(AppText.localized("この検索条件を読み込めませんでした。")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(loading || submitting)
                    .accessibilityIdentifier("browser-history-query-\(index)").accessibilityLabel(title(entry))
                }.onDelete { offsets in
                    let removed = offsets.map { entries[$0] }
                    do {
                        for entry in removed { entries = try BrowserSearchHistory.remove(entry, key: preferenceKey) }
                    } catch { self.error = AppText.localized("検索履歴を保存できませんでした。") }
                }
            }
            .environment(\.editMode, $editMode)
            .accessibilityIdentifier("browser-history-list")
            .studyThemeSurface().navigationTitle(AppText.localized("最近の検索"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.localized("閉じる")) { active = false; dismiss() }.accessibilityIdentifier("browser-history-close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(AppText.localized("履歴を消去"), role: .destructive) { clearing = true }
                        .disabled(entries.isEmpty || submitting).accessibilityIdentifier("browser-history-clear")
                }
                ToolbarItem(placement: .secondaryAction) {
                    EditButton().environment(\.editMode, $editMode).disabled(submitting || (entries.isEmpty && editMode != .active))
                }
            }
            .task(id: entries) {
                loading = true
                var resolved: [BrowserSearchRequest: String] = [:]
                for entry in entries {
                    if Task.isCancelled { return }
                    if let query = try? await resolve(entry) { resolved[entry] = entry.hasFilters ? query : entry.query }
                }
                guard !Task.isCancelled, active else { return }
                titles = resolved; loading = false
            }
            .onDisappear { active = false }
            .confirmationDialog(AppText.localized("検索履歴をすべて消去しますか？"), isPresented: $clearing, titleVisibility: .visible) {
                Button(AppText.localized("履歴を消去"), role: .destructive) {
                    BrowserSearchHistory.clear(key: preferenceKey); entries = []; editMode = .inactive
                }.accessibilityIdentifier("browser-history-clear-confirm")
                Button(AppText.localized("キャンセル"), role: .cancel) {}
            }
            .alert(AppText.localized("検索できませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
    private func choose(_ entry: BrowserSearchRequest) {
        submitting = true
        Task {
            defer { submitting = false }
            do {
                let resolved = try await resolve(entry)
                guard active else { return }
                try select(entry, entry.hasFilters ? resolved : entry.query)
                active = false; dismiss()
            } catch { if active { self.error = AppText.localized("この検索条件を読み込めませんでした。") } }
        }
    }
}
