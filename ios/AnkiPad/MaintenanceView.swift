import SwiftUI

struct MaintenanceView: View {
    @ObservedObject var model: StudyModel
    @Environment(\.dismiss) private var dismiss
    @State private var backups: [CollectionBackup] = []
    @State private var sharing: BackupExport?
    @State private var sharedCopy: BackupExport?
    @State private var restoring: CollectionBackup?
    @State private var report = ""
    @State private var unused: [String] = []
    @State private var error: String?
    @State private var busy = false
    @State private var confirmTrash = false
    @State private var confirmEmptyTrash = false
    var body: some View {
        NavigationStack {
            List {
                Section("コレクション") {
                    Button("今すぐバックアップ") { run { try await model.engine.backup(); backups = try await model.engine.backups(); report = "バックアップを作成しました" } }.accessibilityIdentifier("backup-create")
                    Button("データベースをチェック") {
                        run {
                            let problems = try await model.engine.checkDatabase()
                            report = problems.isEmpty ? "データベースに問題はありません。" : problems.joined(separator: "\n")
                        }
                    }
                    Button("画像・音声をチェック") {
                        run {
                            let result = try await model.engine.checkMedia()
                            report = result["report"] as? String ?? "チェックが終了しました。"
                            unused = result["unused"] as? [String] ?? []
                        }
                    }
                    if !unused.isEmpty { Button("未使用ファイル\(unused.count)件をゴミ箱へ", role: .destructive) { confirmTrash = true } }
                    Button("メディアのゴミ箱を復元") { run { try await model.engine.restoreMediaTrash(); report = "ゴミ箱のファイルを復元しました" } }
                    Button("メディアのゴミ箱を空にする", role: .destructive) { confirmEmptyTrash = true }
                }.disabled(busy || model.busy)
                if busy { ProgressView("処理中…") }
                if !report.isEmpty { Section("結果") { Text(report).textSelection(.enabled) } }
                Section("保存済みバックアップ") {
                    ForEach(backups) { backup in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(backup.date.formatted()).foregroundStyle(.primary)
                            Text(backup.fileName).font(.caption).textSelection(.enabled)
                            Text(ByteCountFormatter.string(fromByteCount: backup.size, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button { run { let export = try await model.engine.exportBackup(backup); sharedCopy = export; sharing = export } } label: {
                                    Label("共有・ファイルに保存", systemImage: "square.and.arrow.up")
                                }.accessibilityIdentifier("backup-share-" + backup.id)
                                Spacer()
                                Button("復元", role: .destructive) { restoring = backup }
                                    .accessibilityIdentifier("backup-restore-" + backup.id)
                            }.buttonStyle(.bordered)
                        }.disabled(busy || model.busy)

                    }
                    Text("バックアップはカードと学習履歴を保存します。画像・音声は含みません。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("バックアップとチェック")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss(); model.refreshAfterEditing() }.accessibilityIdentifier("maintenance-close").disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .sheet(item: $sharing, onDismiss: { releaseSharedBackup() }) { export in
                ShareSheet(url: export.url)
            }
            .confirmationDialog("このバックアップに戻しますか？", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
                if let backup = restoring {
                    Button("復元", role: .destructive) { run { try await model.engine.restoreCollection(backup.url); restoring = nil; report = "バックアップを復元しました"; backups = try await model.engine.backups(); model.refreshAfterEditing() } }
                }
            } message: { Text("現在のコレクションを置き換えます。復元前のバックアップも保存します。") }
            .confirmationDialog("未使用の画像・音声をゴミ箱に移しますか？", isPresented: $confirmTrash) {
                Button("ゴミ箱へ移動", role: .destructive) { run { try await model.engine.trashMedia(unused); unused = []; report = "未使用ファイルをゴミ箱に移しました" } }
            }
            .confirmationDialog("ゴミ箱のメディアを完全に削除しますか？", isPresented: $confirmEmptyTrash) {
                Button("完全に削除", role: .destructive) { run { try await model.engine.emptyMediaTrash(); report = "ゴミ箱を空にしました" } }
            }
            .alert("処理できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
            .task { do { backups = try await model.engine.backups() } catch { self.error = error.localizedDescription } }
        }
    }
    private func releaseSharedBackup() {
        sharedCopy?.removeTemporaryCopy()
        sharedCopy = nil
    }
    private func run(_ operation: @escaping () async throws -> Void) {
        guard !busy, !model.busy else { return }
        busy = true
        Task { defer { busy = false }; do { try await operation() } catch { self.error = error.localizedDescription } }
    }
}
