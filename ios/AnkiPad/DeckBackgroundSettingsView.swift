import SwiftUI
import UniformTypeIdentifiers

struct DeckBackgroundSettingsView: View {
    let root: URL
    @Binding var change: DeckBackgroundChange
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var choosingPhoto = false
    @State private var choosingFile = false
    @State private var confirmingRemove = false
    @State private var canRemove = false
    @State private var error: String?
    @State private var busy = true
    @State private var pendingData: Data?
    @State private var pendingFile: URL?
    @State private var pendingPhotoError: String?
    @State private var selection = UUID()

    var body: some View {
        Form {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240)
                    .accessibilityLabel("背景のプレビュー").accessibilityIdentifier("deck-background-preview")
                    .accessibilityValue("\(image.cgImage?.width ?? 0) × \(image.cgImage?.height ?? 0)")
            } else { Text("背景画像なし").accessibilityIdentifier("deck-background-none") }
            Section {
                Button("写真から選ぶ") {
                    pendingData = nil; pendingFile = nil; pendingPhotoError = nil; choosingPhoto = true
                }.accessibilityIdentifier("deck-background-photo")
                Button("ファイルから選ぶ") {
                    pendingData = nil; pendingFile = nil; choosingFile = true
                }.accessibilityIdentifier("deck-background-file")
                if canRemove {
                    Button("背景画像を削除", role: .destructive) { confirmingRemove = true }.accessibilityIdentifier("deck-background-remove")
                }
            }
            Text("デッキ一覧に中央で切り抜いて表示します。10MiB未満の画像を選んでください。変更は設定画面の「保存」で適用します。")
                .font(.caption).foregroundStyle(.secondary)
            if busy { ProgressView() }
        }
        .studyThemeSurface()
        .disabled(busy)
        .navigationTitle("デッキ一覧の背景")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() }.disabled(busy).accessibilityIdentifier("deck-background-done") } }
        .alert("背景画像を削除しますか？", isPresented: $confirmingRemove) {
            Button("削除", role: .destructive) { change = .remove; image = nil; canRemove = false }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("画像を読み込めませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("閉じる", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
        .sheet(isPresented: $choosingPhoto, onDismiss: {
            if let message = pendingPhotoError { error = message; pendingPhotoError = nil }
            else if pendingData != nil { selection = UUID() }
        }) {
            PhotoSelectionView(maximumBytes: DeckBackgroundStore.maximumFileBytes) { data, message in
                pendingPhotoError = message; pendingData = data
            }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url): pendingFile = url; pendingData = nil; selection = UUID()
            case .failure(let error): self.error = error.localizedDescription
            }
        }
        .task(id: selection) {
            busy = true
            defer { if !Task.isCancelled { busy = false } }
            do {
                if pendingData == nil && pendingFile == nil {
                    switch change {
                    case .unchanged:
                        canRemove = FileManager.default.fileExists(atPath: root.appendingPathComponent(DeckBackgroundStore.filename).path)
                        let loaded = try await DeckBackgroundStore.shared.load(root: root)
                        guard !Task.isCancelled else { return }; image = loaded
                    case .remove: image = nil; canRemove = false
                    case .replace(let data):
                        let loaded = try await DeckBackgroundStore.shared.prepare(data)
                        guard !Task.isCancelled else { return }; image = loaded; canRemove = true
                    }
                    return
                }
                let result: (Data, UIImage)
                if let file = pendingFile { result = try await DeckBackgroundStore.shared.prepareFile(file) }
                else if let data = pendingData { result = (data, try await DeckBackgroundStore.shared.prepare(data)) }
                else { return }
                guard !Task.isCancelled else { return }
                change = .replace(result.0); image = result.1; canRemove = true
                pendingData = nil; pendingFile = nil
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
