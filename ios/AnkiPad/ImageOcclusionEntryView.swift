import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct ImageOcclusionEntryView: View {
    @ObservedObject var model: StudyModel
    let initialFile: IncomingImportFile?
    private let engine: Engine
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var pickingPhoto = false
    @State private var photoResult: Result<Data, EngineError>?
    @State private var cameraResult: Result<Data, EngineError>?
    @State private var camera = false
    @State private var page: BackendPageRequest?
    @State private var deckID = "1"
    @State private var error: String?
    @State private var busy = false
    @State private var receivedImageOpened = false
    init(model: StudyModel, initialFile: IncomingImportFile? = nil) {
        self.model = model; self.initialFile = initialFile; engine = model.engine
        _deckID = State(initialValue: model.selected?.id ?? model.decks.first(where: { $0.isSelected })?.id ?? model.decks.first?.id ?? "1")
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker(AppText.localized("デッキ"), selection: $deckID) { ForEach(model.decks) { Text($0.name).tag($0.id) } }
                Text(AppText.localized("画像を選び、覚えたい部分をマスクで隠します。マスクごとに穴埋めカードを作成します。"))
                if let initialFile {
                    Text(initialFile.name).foregroundStyle(.secondary)
                    Button(AppText.localized("受け取った画像を開く")) { openReceivedImage(initialFile) }
                        .accessibilityIdentifier("occlusion-received-image")
                }
                Button(AppText.localized("ファイルから画像を選択"), systemImage: "folder") { picking = true }.accessibilityIdentifier("occlusion-select-image")
                Button(AppText.localized("写真から選択"), systemImage: "photo") { pickingPhoto = true }.accessibilityIdentifier("occlusion-select-photo")
                Button(AppText.localized("写真を撮影"), systemImage: "camera") { camera = true }.disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                if busy { ProgressView() }
            }
            .disabled(busy)
            .interactiveDismissDisabled(busy)
            .studyThemeSurface().navigationTitle(AppText.localized("画像穴埋め"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(AppText.localized("閉じる")) { dismiss() }.disabled(busy).accessibilityIdentifier("occlusion-entry-close") } }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.image]) { result in
                switch result {
                case .failure(let failure): error = failure.localizedDescription
                case .success(let url):
                    busy = true
                    Task {
                        defer { busy = false }
                        do { try await open(try await engine.prepareImport(url)) }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
            .sheet(isPresented: $pickingPhoto, onDismiss: {
                let result = photoResult; photoResult = nil; openPhoto(result)
            }) {
                PhotoSelectionView { data, error in
                    if let data { photoResult = .success(data) }
                    else { photoResult = .failure(EngineError(message: error ?? AppText.localized("画像を読み込めませんでした。"))) }
                }
            }
            .sheet(isPresented: $camera, onDismiss: {
                let result = cameraResult; cameraResult = nil; openPhoto(result)
            }) {
                CameraCaptureView { image in
                    if let data = image.jpegData(compressionQuality: 0.95) { cameraResult = .success(data) }
                    else { cameraResult = .failure(EngineError(message: AppText.localized("写真を変換できませんでした。"))) }
                }
            }
            .sheet(item: $page, onDismiss: { dismiss() }) { BackendPageView(model: model, request: $0, onClose: { page = nil }) }
            .alert(AppText.localized("画像を開けませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
            .task {
                guard let initialFile, !receivedImageOpened else { return }
                receivedImageOpened = true
                openReceivedImage(initialFile)
            }
        }
    }
    private func openPhoto(_ result: Result<Data, EngineError>?) {
        guard let result else { return }
        switch result {
        case .failure(let error): self.error = error.localizedDescription
        case .success(let data):
            busy = true
            Task {
                defer { busy = false }
                do { try await open(try await engine.prepareOcclusionPhoto(data)) }
                catch { self.error = error.localizedDescription }
            }
        }
    }
    private func openReceivedImage(_ file: IncomingImportFile) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await open(try await engine.prepareImport(file.url)) }
            catch { self.error = error.localizedDescription }
        }
    }
    private func open(_ local: URL) async throws {
        try Task.checkCancellation()
        try await engine.select(deckID)
        try Task.checkCancellation()
        guard let path = local.path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { throw EngineError(message: AppText.localized("画像のパスを作成できませんでした。")) }
        page = BackendPageRequest(path: "image-occlusion/" + path, title: AppText.localized("画像穴埋め"))
    }
}
