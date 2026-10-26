import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import ImageIO

struct NoteEditorView: View {
    @ObservedObject var model: StudyModel
    let request: EditorRequest
    @Environment(\.dismiss) private var dismiss
    @State private var document: NoteDocument?
    @State private var types: [NamedID] = []
    @State private var typeID = ""
    @State private var busy = false
    @State private var error: String?
    @State private var importingMedia = false
    @State private var recordingAudio = false
    @State private var choosingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var camera = false
    @State private var pendingImage: NoteImageEditRequest?
    @State private var editingImage: NoteImageEditRequest?
    @State private var selectingImage: FieldImageSelection?
    @State private var imageSelectionError: String?
    @State private var mediaField = 0
    @State private var showDiscard = false
    @State private var dirty = false
    @State private var added = false
    @State private var draftPreview = false
    @State private var copied: EditorRequest?
    @State private var isOcclusion = false
    @State private var fieldWarning: String?
    @State private var changingType: BackendPageRequest?
    @State private var expanded: Set<Int> = []
    @AppStorage("visualNoteEditor") private var visualEditor = false
    @AppStorage("closeAfterAdd") private var closeAfterAdd = false
    var body: some View { NavigationStack { loadedContent } }
    private var editorForm: some View {
            Form {
                if let current = document {
                    Section {
                        if request.isNew {
                            Picker("ノートタイプ", selection: $typeID) { ForEach(types) { Text($0.name).tag($0.id) } }
                                .onChange(of: typeID) { _, next in load(type: next) }
                        } else {
                            LabeledContent("ノートタイプ", value: types.first(where: { $0.id == current.typeID })?.name ?? "")
                            if isOcclusion {
                                Button("画像穴埋めのマスクを編集", systemImage: "rectangle.dashed") {
                                    changingType = BackendPageRequest(path: "image-occlusion/" + current.id, title: "画像穴埋め", noteIDs: [current.id])
                                }.disabled(dirty).accessibilityIdentifier("occlusion-edit")
                            }
                            Button(dirty ? "保存してノートタイプを変更" : "ノートタイプを変更") {
                                busy = true
                                Task {
                                    defer { busy = false }
                                    do {
                                        if dirty { try await model.engine.saveNote(current, isNew: false); dirty = false }
                                        changingType = BackendPageRequest(path: "change-notetype/" + current.typeID, title: "ノートタイプを変更", noteIDs: [current.id])
                                    } catch { self.error = error.localizedDescription }
                                }
                            }
                        }
                        Picker("デッキ", selection: Binding(get: { document?.deckID ?? "1" }, set: { document?.deckID = $0; dirty = true })) {
                            ForEach(model.decks) { Text($0.name).tag($0.id) }
                        }
                    }
                    Toggle("ビジュアル編集", isOn: $visualEditor)
                    ForEach(current.fields.indices, id: \.self) { index in
                        Section {
                            DisclosureGroup(isExpanded: Binding(get: { expanded.contains(index) }, set: { value in if value { expanded.insert(index) } else { expanded.remove(index) } })) {
                            if visualEditor {
                                RichFieldEditor(text: Binding(get: { document?.fields[index] ?? "" }, set: { document?.fields[index] = $0; dirty = true }), media: model.engine.media, label: "note-field-\(index)", fontName: current.fieldConfigs.indices.contains(index) ? current.fieldConfigs[index]["fontName"] as? String ?? "Arial" : "Arial", fontSize: current.fieldConfigs.indices.contains(index) ? current.fieldConfigs[index]["fontSize"] as? Int ?? 20 : 20, rtl: current.fieldConfigs.indices.contains(index) && current.fieldConfigs[index]["rtl"] as? Bool == true)
                            } else {
                            TextEditor(text: Binding(get: { document?.fields[index] ?? "" }, set: { document?.fields[index] = $0; dirty = true }))
                                .frame(minHeight: 110).accessibilityIdentifier("note-field-\(index)")
                                .autocorrectionDisabled().textInputAutocapitalization(.never)
                                .font(.custom(current.fieldConfigs.indices.contains(index) ? current.fieldConfigs[index]["fontName"] as? String ?? "Arial" : "Arial", size: CGFloat(current.fieldConfigs.indices.contains(index) ? current.fieldConfigs[index]["fontSize"] as? Int ?? 20 : 20)))
                                .environment(\.layoutDirection, current.fieldConfigs.indices.contains(index) && current.fieldConfigs[index]["rtl"] as? Bool == true ? .rightToLeft : .leftToRight)
                            }
                            Menu("添付", systemImage: "paperclip") {
                                Button("ファイルから画像・音声を追加", systemImage: "folder") { mediaField = index; importingMedia = true }
                                Button("写真ライブラリから追加", systemImage: "photo.on.rectangle") { mediaField = index; choosingPhoto = true }
                                Button("写真を撮影", systemImage: "camera") { mediaField = index; camera = true }.disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                                Button("フィールド内の画像を編集", systemImage: "photo.badge.arrow.down") {
                                    let html = document?.fields[index] ?? ""
                                    selectingImage = FieldImageSelection(field: index, html: html, images: FieldImageReference.extract(html))
                                }
                                Button("音声を録音", systemImage: "mic") { mediaField = index; recordingAudio = true }
                            }
                            if current.fieldConfigs.indices.contains(index), let description = current.fieldConfigs[index]["description"] as? String, !description.isEmpty { Text(description).font(.footnote).foregroundStyle(.secondary) }
                            } label: { Text(index < current.fieldNames.count ? current.fieldNames[index] : "フィールド \(index + 1)") }
                        }
                    }
                    Section {
                        Button("保存せずにプレビュー", systemImage: "eye") { draftPreview = true }.accessibilityIdentifier("note-preview")
                        Button("このノートを複製", systemImage: "doc.on.doc") { copied = EditorRequest(deckID: current.deckID, copiedDocument: current) }
                    }
                    Section("タグ（空白で区切る）") {
                        TextField("タグ", text: Binding(get: { document?.tags ?? "" }, set: { document?.tags = $0; dirty = true }))
                            .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("note-tags")
                    }
                    Section { Text("フィールドはHTMLを含む元の内容を編集できます。穴埋めは {{c1::内容}} の形式で入力します。")
                        .font(.footnote).foregroundStyle(.secondary) }
                } else { ProgressView() }
                if busy { ProgressView("保存中…") }
            }.accessibilityIdentifier("note-form")
    }
    private var navigationContent: some View {
        editorForm
            .disabled(busy || model.busy)
            .safeAreaInset(edge: .top) {
                if added { Text("ノートを追加しました").foregroundStyle(.green).padding(8).accessibilityIdentifier("note-added") }
            }
            .navigationTitle(request.isNew ? "ノートを追加" : "ノートを編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(request.isNew ? "閉じる" : "キャンセル") { if dirty { showDiscard = true } else { dismiss() } }.accessibilityIdentifier("note-close") }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(document == nil || busy).accessibilityIdentifier("note-save") }
            }
            .interactiveDismissDisabled(dirty || busy)
            .confirmationDialog("変更を破棄しますか？", isPresented: $showDiscard) { Button("破棄", role: .destructive) { dismiss() } }
            .alert("このまま保存しますか？", isPresented: Binding(get: { fieldWarning != nil }, set: { if !$0 { fieldWarning = nil } })) {
                Button("保存") { fieldWarning = nil; save(force: true) }
                Button("キャンセル", role: .cancel) { fieldWarning = nil }
            } message: { Text(fieldWarning ?? "") }
    }
    private var schemaContent: some View {
        navigationContent
            .sheet(item: $changingType, onDismiss: {
                guard let current = document else { return }
                Task {
                    do {
                        let cards = try await model.engine.call("NotesService.CardsOfNote", ["nid": current.id])["cids"] as? [String] ?? []
                        let updated = try await model.engine.noteDocument(cardID: cards.first, noteID: cards.isEmpty ? current.id : nil, typeID: nil, deckID: current.deckID)
                        document = updated
                        typeID = updated.typeID
                        types = try await model.engine.noteTypes()
                        expandFields(updated)
                        model.refreshAfterEditing()
                    } catch { self.error = error.localizedDescription }
                }
            }) { BackendPageView(model: model, request: $0) }
    }
    private var mediaContent: some View {
        schemaContent
            .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
            .onChange(of: photo) { _, item in
                guard let item else { return }
                let field = mediaField
                busy = true
                Task {
                    defer { busy = false }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw EngineError(message: "画像を読み込めませんでした。") }
                        pendingImage = NoteImageEditRequest(image: image, field: field)
                        presentPendingImage()
                    } catch { self.error = error.localizedDescription }
                    photo = nil
                }
            }
            .onChange(of: choosingPhoto) { _, presented in if !presented { presentPendingImage() } }
            .sheet(isPresented: $camera, onDismiss: presentPendingImage) {
                CameraCaptureView { image in pendingImage = NoteImageEditRequest(image: image, field: mediaField) }
            }
            .sheet(item: $selectingImage, onDismiss: presentPendingImage) { selection in
                NavigationStack {
                    List(selection.images) { image in
                        Button(image.source) { openFieldImage(image, selection: selection) }
                    }
                    .overlay { if selection.images.isEmpty { ContentUnavailableView("編集できる画像がありません", systemImage: "photo") } }
                    .navigationTitle("画像を選択")
                    .alert("画像を開けませんでした", isPresented: Binding(get: { imageSelectionError != nil }, set: { if !$0 { imageSelectionError = nil } })) {
                        Button("閉じる", role: .cancel) { imageSelectionError = nil }
                    } message: { Text(imageSelectionError ?? "") }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { selectingImage = nil } } }
                }
            }
            .sheet(item: $editingImage) { request in
                NoteImageEditorView(request: request) { image, changed in
                    if !changed, let data = request.originalData, let ext = request.originalExtension {
                        try await insertImageData(data, extension: ext, field: request.field, replacing: request)
                    } else { try await insertPhoto(image, field: request.field, replacing: request) }
                }
            }
            .sheet(isPresented: $draftPreview) {
                if let document { DraftNotePreviewView(model: model, document: document) }
            }
            .sheet(item: $copied) { NoteEditorView(model: model, request: $0) }
            .sheet(isPresented: $recordingAudio) {
                AudioRecorderView { url in
                    let name = try await model.engine.addMedia(url)
                    if document?.fields.indices.contains(mediaField) == true { document?.fields[mediaField] += "[sound:\(name)]"; dirty = true }
                }
            }
            .onChange(of: importingMedia) { _, presented in if !presented { presentPendingImage() } }
            .fileImporter(isPresented: $importingMedia, allowedContentTypes: [.image, .audio, .movie, .data]) { result in
                switch result {
                case .failure(let failure): error = failure.localizedDescription
                case .success(let url): insertMedia(url)
                }
            }
    }
    private var loadedContent: some View {
        mediaContent
            .alert("処理できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
            .task {
                do {
                    types = try await model.engine.noteTypes()
                    var loaded = try await model.engine.noteDocument(cardID: request.cardID, noteID: request.noteID, typeID: request.copiedDocument?.typeID, deckID: request.deckID)
                    if let source = request.copiedDocument { loaded.fields = source.fields; loaded.tags = source.tags; dirty = true }
                    typeID = loaded.typeID
                    document = loaded
                    isOcclusion = (try? await model.engine.call("ImageOcclusionService.GetImageOcclusionFields", ["notetypeId": loaded.typeID]))?["fields"] != nil
                    expandFields(loaded)
                } catch { self.error = error.localizedDescription }
            }
    }
    private func load(type: String) {
        guard request.isNew, type != document?.typeID else { return }
        Task {
            do {
                var replacement = try await model.engine.noteDocument(cardID: nil, typeID: type, deckID: document?.deckID ?? request.deckID)
                if let previous = document {
                    for index in replacement.fields.indices where previous.fields.indices.contains(index) { replacement.fields[index] = previous.fields[index] }
                    replacement.tags = previous.tags
                }
                document = replacement
                expandFields(replacement)
                dirty = true
            } catch { self.error = error.localizedDescription }
        }
    }
    private func expandFields(_ document: NoteDocument) {
        expanded = Set(document.fields.indices.filter { !document.fieldConfigs.indices.contains($0) || document.fieldConfigs[$0]["collapsed"] as? Bool != true })
    }
    private func save(force: Bool = false) {
        guard let document, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                if !force {
                    let state = try await model.engine.checkNoteDocument(document)
                    let warnings = ["EMPTY": "最初のフィールドが空です。", "DUPLICATE": "同じ最初のフィールドを持つノートがあります。", "MISSING_CLOZE": "穴埋めの指定がありません。", "NOTETYPE_NOT_CLOZE": "このノートタイプでは穴埋めを生成できません。", "FIELD_NOT_CLOZE": "穴埋めのフィルターを設定していないフィールドに穴埋めがあります。"]
                    if let warning = warnings[state] { fieldWarning = warning; return }
                }
                try await model.engine.saveNote(document, isNew: request.isNew)
                dirty = false
                model.refreshAfterEditing()
                if request.isNew && !closeAfterAdd {
                    var next = try await model.engine.noteDocument(cardID: nil, typeID: document.typeID, deckID: document.deckID)
                    next.tags = document.tags
                    self.document = next
                    expandFields(next)
                    added = true
                } else { dismiss() }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func openFieldImage(_ reference: FieldImageReference, selection: FieldImageSelection) {
        do {
            let root = model.engine.media.standardizedFileURL.resolvingSymlinksInPath()
            let url = root.appendingPathComponent(reference.source).standardizedFileURL.resolvingSymlinksInPath()
            guard url.deletingLastPathComponent() == root else { throw EngineError(message: "画像の場所を確認できませんでした。") }
            let data = try Data(contentsOf: url)
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
                  let image = UIImage(data: data) else { throw EngineError(message: "この画像形式は編集できません。") }
            pendingImage = NoteImageEditRequest(image: image, field: selection.field, originalData: data,
                originalExtension: url.pathExtension, originalField: selection.html, replacementRange: reference.range)
            selectingImage = nil
        } catch { imageSelectionError = error.localizedDescription }
    }
    private func presentPendingImage() {
        guard !camera, !choosingPhoto, !importingMedia, selectingImage == nil, editingImage == nil, let pendingImage else { return }
        self.pendingImage = nil
        editingImage = pendingImage
    }
    private func insertPhoto(_ image: UIImage, field: Int, replacing request: NoteImageEditRequest? = nil) async throws {
        guard document?.fields.indices.contains(field) == true else { throw EngineError(message: "画像の挿入先が見つかりません。") }
        busy = true
        defer { busy = false }
        let preferences = try await model.engine.preferences()
        let asPNG = (preferences["editing"] as? [String: Any])?["pasteImagesAsPng"] as? Bool ?? false
        guard let data = asPNG ? image.pngData() : image.jpegData(compressionQuality: 0.95) else { throw EngineError(message: "写真を変換できませんでした。") }
        try await insertImageData(data, extension: asPNG ? "png" : "jpg", field: field, replacing: request)
    }
    private func insertImageData(_ data: Data, extension ext: String, field: Int, replacing request: NoteImageEditRequest? = nil) async throws {
        guard document?.fields.indices.contains(field) == true else { throw EngineError(message: "画像の挿入先が見つかりません。") }
        busy = true
        defer { busy = false }
        if let original = request?.originalField, document?.fields[field] != original {
            throw EngineError(message: "フィールドが変更されています。画像を選び直してください。")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("photo-" + UUID().uuidString + "." + ext)
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let name = try await model.engine.addMedia(url)
        let escaped = name.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;")
        if let original = request?.originalField, let range = request?.replacementRange {
            guard document?.fields.indices.contains(field) == true, document?.fields[field] == original else { throw EngineError(message: "フィールドが変更されています。画像を選び直してください。") }
            document?.fields[field] = (original as NSString).replacingCharacters(in: range, with: escaped)
            dirty = true
        } else if document?.fields.indices.contains(field) == true {
            document?.fields[field] += "<img src=\"\(escaped)\">"; dirty = true
        }
    }
    private func insertMedia(_ url: URL) {
        let field = mediaField
        busy = true
        Task {
            defer { busy = false }
            do {
                let type = UTType(filenameExtension: url.pathExtension)
                if type?.conforms(to: .image) == true {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    if let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
                       let image = UIImage(data: data) {
                        pendingImage = NoteImageEditRequest(image: image, field: field, originalData: data, originalExtension: url.pathExtension)
                        presentPendingImage()
                        return
                    }
                }
                let name = try await model.engine.addMedia(url)
                let encoded = name.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;")
                let content: String
                if type?.conforms(to: .image) == true { content = "<img src=\"\(encoded)\">" }
                else if type?.conforms(to: .movie) == true { content = "<video controls src=\"\(encoded)\"></video>" }
                else { content = "[sound:\(name)]" }
                if document?.fields.indices.contains(field) == true { document?.fields[field] += content; dirty = true }
            } catch { self.error = error.localizedDescription }
        }
    }
}
