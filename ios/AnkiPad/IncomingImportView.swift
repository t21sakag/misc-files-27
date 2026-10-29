import SwiftUI

struct IncomingImportView: View {
    @ObservedObject var model: StudyModel
    let file: IncomingImportFile
    let begin: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReplacement = false
    var body: some View {
        NavigationStack {
            Form {
                Section(AppText.localized("ファイル")) {
                    Text(file.name).textSelection(.enabled)
                    Text(ByteCountFormatter.string(fromByteCount: file.byteCount, countStyle: .file))
                        .foregroundStyle(.secondary)
                }
                Section(AppText.localized("取り込み先")) { Text(model.currentProfile.name) }
                if file.kind == .collection {
                    Section {
                        Text(AppText.localized("現在のコレクションを読み込むファイルで置き換えます。現在のデータはバックアップに保存します。"))
                        Button(AppText.localized("バックアップして置き換える"), role: .destructive) { confirmingReplacement = true }
                            .accessibilityIdentifier("incoming-import-replace")
                    }
                } else {
                    Section {
                        Button(AppText.localized("取り込む"), action: begin).accessibilityIdentifier("incoming-import-confirm")
                    }
                }
            }
            .disabled(model.busy || model.isSyncing)
            .studyThemeSurface().navigationTitle(AppText.localized("取り込みを確認"))
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(AppText.localized("キャンセル")) { dismiss() }.accessibilityIdentifier("incoming-import-cancel")
            } }
            .confirmationDialog(AppText.localized("コレクションを置き換えますか？"), isPresented: $confirmingReplacement, titleVisibility: .visible) {
                Button(AppText.localized("バックアップして置き換える"), role: .destructive, action: begin)
                Button(AppText.localized("キャンセル"), role: .cancel) {}
            } message: { Text(AppText.localized("現在のコレクションを置き換えます。復元前のバックアップも保存します。")) }
        }
    }
}
