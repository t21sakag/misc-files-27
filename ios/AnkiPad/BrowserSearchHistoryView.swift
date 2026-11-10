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
    let save: @MainActor (String, BrowserSearchRequest) async throws -> Void
    let select: (BrowserSearchRequest, String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var clearing = false
    @State private var editMode: EditMode = .inactive
    @State private var titles: [BrowserSearchRequest: String] = [:]
    @State private var loading = true
    @State private var submitting = false
    @State private var active = true
    @State private var error: String?
    @State private var errorTitle = AppText.localized("検索できませんでした")
    @State private var bookmarkEntry: BrowserSearchRequest?
    @State private var bookmarkName = ""
    @State private var saving = false
    private func title(_ entry: BrowserSearchRequest) -> String {
        titles[entry] ?? (entry.query.isEmpty ? AppText.localized("この検索条件を読み込めませんでした。") : entry.query)
    }
    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty { Text(AppText.localized("まだ検索履歴がありません。")) }
                ForEach(Array(entries.enumerated()), id: \.element) { index, entry in
                    HStack {
                        Button { choose(entry) } label: {
                            VStack(alignment: .leading) {
                                Text(title(entry)).lineLimit(3)
                                if !loading && titles[entry] == nil {
                                    Text(AppText.localized("この検索条件を読み込めませんでした。")).font(.caption).foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderless)
                        .disabled(loading)
                        .accessibilityIdentifier("browser-history-query-\(index)").accessibilityLabel(title(entry))
                        Button {
                            bookmarkName = ""; bookmarkEntry = entry
                        } label: {
                            Image(systemName: "star").frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .disabled(loading || titles[entry] == nil)
                        .accessibilityIdentifier("browser-history-save-\(index)")
                        .accessibilityLabel(AppText.localized("この検索を保存") + " " + title(entry))
                    }
                }.onDelete { offsets in
                    let removed = offsets.map { entries[$0] }
                    do {
                        for entry in removed { entries = try BrowserSearchHistory.remove(entry, key: preferenceKey) }
                    } catch {
                        errorTitle = AppText.localized("処理できませんでした")
                        self.error = AppText.localized("検索履歴を保存できませんでした。")
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .disabled(submitting || saving)
            .accessibilityIdentifier("browser-history-list")
            .studyThemeSurface().navigationTitle(AppText.localized("最近の検索"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.localized("閉じる")) { active = false; dismiss() }
                        .disabled(saving).accessibilityIdentifier("browser-history-close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(AppText.localized("履歴を消去"), role: .destructive) { clearing = true }
                        .disabled(entries.isEmpty || submitting || saving).accessibilityIdentifier("browser-history-clear")
                }
                ToolbarItem(placement: .secondaryAction) {
                    EditButton().environment(\.editMode, $editMode).disabled(submitting || saving || (entries.isEmpty && editMode != .active))
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
            .alert(AppText.localized("検索を保存"), isPresented: Binding(get: { bookmarkEntry != nil }, set: { if !$0 { bookmarkEntry = nil } }), presenting: bookmarkEntry) { entry in
                TextField(AppText.localized("名前"), text: $bookmarkName)
                Button(AppText.localized("保存")) { saveEntry(entry, name: bookmarkName) }.disabled(bookmarkName.isEmpty)
                Button(AppText.localized("キャンセル"), role: .cancel) {}
            }
            .alert(errorTitle, isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) {}
            } message: { Text(error ?? "") }
        }.interactiveDismissDisabled(saving)
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
            } catch {
                if active {
                    errorTitle = AppText.localized("検索できませんでした")
                    self.error = AppText.localized("この検索条件を読み込めませんでした。")
                }
            }
        }
    }
    private func saveEntry(_ entry: BrowserSearchRequest, name: String) {
        saving = true
        Task {
            defer { saving = false }
            do {
                guard active else { return }
                try await save(name, entry)
            } catch {
                if active {
                    errorTitle = AppText.localized("処理できませんでした")
                    self.error = error.localizedDescription
                }
            }
        }
    }
}
