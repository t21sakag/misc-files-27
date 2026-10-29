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
                Section(AppText.localized("コレクション")) {
                    Button(AppText.localized("今すぐバックアップ")) { run { try await model.engine.backup(); backups = try await model.engine.backups(); report = AppText.localized("バックアップを作成しました") } }.accessibilityIdentifier("backup-create")
                    Button(AppText.localized("データベースをチェック")) {
                        run {
                            let problems = try await model.engine.checkDatabase()
                            report = problems.isEmpty ? AppText.localized("データベースに問題はありません。") : problems.joined(separator: "\n")
                        }
                    }
                    Button(AppText.localized("画像・音声をチェック")) {
                        run {
                            let result = try await model.engine.checkMedia()
                            report = result["report"] as? String ?? AppText.localized("チェックが終了しました。")
                            unused = result["unused"] as? [String] ?? []
                        }
                    }
                    if !unused.isEmpty { Button(AppText.localized("未使用ファイル\(unused.count)件をゴミ箱へ"), role: .destructive) { confirmTrash = true } }
                    Button(AppText.localized("メディアのゴミ箱を復元")) { run { try await model.engine.restoreMediaTrash(); report = AppText.localized("ゴミ箱のファイルを復元しました") } }
                    Button(AppText.localized("メディアのゴミ箱を空にする"), role: .destructive) { confirmEmptyTrash = true }
                }.disabled(busy || model.busy)
                if busy { ProgressView(AppText.localized("処理中…")) }
                if !report.isEmpty { Section(AppText.localized("結果")) { Text(report).textSelection(.enabled) } }
                Section(AppText.localized("保存済みバックアップ")) {
                    ForEach(backups) { backup in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(backup.date.formatted()).foregroundStyle(.primary)
                            Text(backup.fileName).font(.caption).textSelection(.enabled)
                            Text(ByteCountFormatter.string(fromByteCount: backup.size, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button { run { let export = try await model.engine.exportBackup(backup); sharedCopy = export; sharing = export } } label: {
                                    Label(AppText.localized("共有・ファイルに保存"), systemImage: "square.and.arrow.up")
                                }.accessibilityIdentifier("backup-share-" + backup.id)
                                Spacer()
                                Button(AppText.localized("復元"), role: .destructive) { restoring = backup }
                                    .accessibilityIdentifier("backup-restore-" + backup.id)
                            }.buttonStyle(.bordered)
                        }.disabled(busy || model.busy)

                    }
                    Text(AppText.localized("バックアップはカードと学習履歴を保存します。画像・音声は含みません。"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("maintenance-form").studyThemeSurface().navigationTitle(AppText.localized("バックアップとチェック"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(AppText.localized("閉じる")) { dismiss(); model.refreshAfterEditing() }.accessibilityIdentifier("maintenance-close").disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .sheet(item: $sharing, onDismiss: { releaseSharedBackup() }) { export in
                ShareSheet(url: export.url)
            }
            .confirmationDialog(AppText.localized("このバックアップに戻しますか？"), isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
                if let backup = restoring {
                    Button(AppText.localized("復元"), role: .destructive) { run { try await model.engine.restoreCollection(backup.url); restoring = nil; report = AppText.localized("バックアップを復元しました"); backups = try await model.engine.backups(); model.refreshAfterEditing() } }.accessibilityIdentifier("backup-confirm-restore")
                }
            } message: { Text(AppText.localized("現在のコレクションを置き換えます。復元前のバックアップも保存します。")) }
            .confirmationDialog(AppText.localized("未使用の画像・音声をゴミ箱に移しますか？"), isPresented: $confirmTrash) {
                Button(AppText.localized("ゴミ箱へ移動"), role: .destructive) { run { try await model.engine.trashMedia(unused); unused = []; report = AppText.localized("未使用ファイルをゴミ箱に移しました") } }
            }
            .confirmationDialog(AppText.localized("ゴミ箱のメディアを完全に削除しますか？"), isPresented: $confirmEmptyTrash) {
                Button(AppText.localized("完全に削除"), role: .destructive) { run { try await model.engine.emptyMediaTrash(); report = AppText.localized("ゴミ箱を空にしました") } }
            }
            .alert(AppText.localized("処理できませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) { error = nil }
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
        report = ""
        busy = true
        Task { defer { busy = false }; do { try await operation() } catch { self.error = error.localizedDescription } }
    }
}
