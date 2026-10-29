import SwiftUI
import UIKit

enum IncomingImportAction { case importDocument, attachToNote, imageOcclusion }

struct IncomingImportView: View {
    @ObservedObject var model: StudyModel
    let file: IncomingImportFile
    let perform: (IncomingImportAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReplacement = false
    @State private var preview: UIImage?
    var body: some View {
        NavigationStack {
            Form {
                Section(AppText.localized("ファイル")) {
                    Text(file.name).textSelection(.enabled)
                    Text(ByteCountFormatter.string(fromByteCount: file.byteCount, countStyle: .file))
                        .foregroundStyle(.secondary)
                    if let preview {
                        Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 240)
                    }
                }
                Section(AppText.localized("取り込み先")) { Text(model.currentProfile.name) }
                if file.kind == .collection {
                    Section {
                        Text(AppText.localized("現在のコレクションを読み込むファイルで置き換えます。現在のデータはバックアップに保存します。"))
                        Button(AppText.localized("バックアップして置き換える"), role: .destructive) { confirmingReplacement = true }
                            .accessibilityIdentifier("incoming-import-replace")
                    }
                } else if file.kind == .image {
                    Section {
                        Button(AppText.localized("画像を付けてノートを追加")) { perform(.attachToNote) }
                            .accessibilityIdentifier("incoming-image-note")
                        Button(AppText.localized("画像穴埋めを追加")) { perform(.imageOcclusion) }
                            .accessibilityIdentifier("incoming-image-occlusion")
                    }
                } else if file.kind == .audio || file.kind == .video {
                    Section {
                        Button(AppText.localized("メディアを付けてノートを追加")) { perform(.attachToNote) }
                            .accessibilityIdentifier("incoming-media-note")
                    }
                } else {
                    Section {
                        Button(AppText.localized("取り込む")) { perform(.importDocument) }.accessibilityIdentifier("incoming-import-confirm")
                    }
                }
            }
            .disabled(model.busy || model.isSyncing)
            .studyThemeSurface().navigationTitle(AppText.localized("取り込みを確認"))
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(AppText.localized("キャンセル")) { dismiss() }.accessibilityIdentifier("incoming-import-cancel")
            } }
            .confirmationDialog(AppText.localized("コレクションを置き換えますか？"), isPresented: $confirmingReplacement, titleVisibility: .visible) {
                Button(AppText.localized("バックアップして置き換える"), role: .destructive) { perform(.importDocument) }
                Button(AppText.localized("キャンセル"), role: .cancel) {}
            } message: { Text(AppText.localized("現在のコレクションを置き換えます。復元前のバックアップも保存します。")) }
            .task(id: file.id) {
                guard file.kind == .image else { return }
                preview = await Task.detached(priority: .utility) { MediaImagePreparation.preview(file.url) }.value
            }
        }
    }
}
