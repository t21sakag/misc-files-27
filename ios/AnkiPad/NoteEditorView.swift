import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import ImageIO

struct NoteEditorView: View {
    @ObservedObject var model: StudyModel
    let request: EditorRequest
    private let engine: Engine
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
    @State private var sharedWarning: String?
    @State private var draftPreview = false
    @State private var copied: EditorRequest?
    @State private var isOcclusion = false
    @State private var fieldWarning: String?
    @State private var changingType: BackendPageRequest?
    @State private var changingEditorFontSize = false
    @State private var fontSizeDraft = ""
    @State private var expanded: Set<Int> = []
    @State private var preservedNewFields: [String] = []
    @State private var typeLoadGeneration = UUID()
    private var extraFieldIndices: [Int] {
        guard request.isNew, let document else { return [] }
        return NewNoteFields.unmapped(preservedNewFields, fieldCount: document.fields.count)
    }
    @AppStorage("visualNoteEditor") private var visualEditor = false
    @AppStorage("capitalizeNoteEditor") private var capitalizeEditor = true
    @AppStorage("noteEditorFontSize") private var editorFontSize = 0
    @AppStorage("closeAfterAdd") private var closeAfterAdd = false
    init(model: StudyModel, request: EditorRequest) {
        self.model = model; self.request = request; engine = model.engine
    }
    var body: some View { NavigationStack { loadedContent } }
    private var editorForm: some View {
            Form {
                if let current = document {
                    Section {
                        if request.isNew {
                            Picker(AppText.localized("ノートタイプ"), selection: $typeID) { ForEach(types) { Text($0.name).tag($0.id) } }
                                .accessibilityIdentifier("note-type")
                                .onChange(of: typeID) { _, next in load(type: next) }
                        } else {
                            LabeledContent(AppText.localized("ノートタイプ"), value: types.first(where: { $0.id == current.typeID })?.name ?? "")
                            if isOcclusion {
                                Button(dirty ? AppText.localized("保存して画像穴埋めのマスクを編集") : AppText.localized("画像穴埋めのマスクを編集"), systemImage: "rectangle.dashed") {
                                    busy = true
                                    Task {
                                        defer { busy = false }
                                        do {
                                            if dirty { try await engine.saveNote(current, isNew: false); dirty = false }
                                            changingType = BackendPageRequest(path: "image-occlusion/" + current.id, title: AppText.localized("画像穴埋め"), noteIDs: [current.id])
                                        } catch { self.error = error.localizedDescription }
                                    }
                                }.accessibilityIdentifier("occlusion-edit")
                            }
                            Button(dirty ? AppText.localized("保存してノートタイプを変更") : AppText.localized("ノートタイプを変更")) {
                                busy = true
                                Task {
                                    defer { busy = false }
                                    do {
                                        if dirty { try await engine.saveNote(current, isNew: false); dirty = false }
                                        changingType = BackendPageRequest(path: "change-notetype/" + current.typeID, title: AppText.localized("ノートタイプを変更"), noteIDs: [current.id])
                                    } catch { self.error = error.localizedDescription }
                                }
                            }
                        }
                        Picker(AppText.localized("デッキ"), selection: Binding(get: { document?.deckID ?? "1" }, set: { document?.deckID = $0; dirty = true })) {
                            ForEach(model.decks) { Text($0.name).tag($0.id) }
                        }
                    }
                    Toggle(AppText.localized("ビジュアル編集"), isOn: $visualEditor)
                    Toggle(AppText.localized("文頭を自動で大文字にする"), isOn: $capitalizeEditor)
                    Button(AppText.localized("編集時の文字サイズ: ") + (editorFontSize > 0 ? String(editorFontSize) : AppText.localized("既定"))) {
                        fontSizeDraft = editorFontSize > 0 ? String(editorFontSize) : ""
                        changingEditorFontSize = true
                    }
                    .alert(AppText.localized("編集時の文字サイズ"), isPresented: $changingEditorFontSize) {
                        TextField("1〜99", text: $fontSizeDraft).keyboardType(.numberPad)
                        Button(AppText.localized("適用")) { if let size = Int(fontSizeDraft), (1...99).contains(size) { editorFontSize = size } }
                            .disabled(Int(fontSizeDraft).map { !(1...99).contains($0) } ?? true)
                        Button(AppText.localized("既定に戻す")) { editorFontSize = 0 }
                        Button(AppText.localized("キャンセル"), role: .cancel) {}
                    }
                    ForEach(current.fields.indices, id: \.self) { index in
                        Section {
                            DisclosureGroup(isExpanded: Binding(get: { expanded.contains(index) }, set: { value in if value { expanded.insert(index) } else { expanded.remove(index) } })) {
                            if visualEditor {
                                RichFieldEditor(text: Binding(get: { document?.fields[index] ?? "" }, set: { document?.fields[index] = $0; dirty = true }), media: engine.media, label: "note-field-\(index)", fontName: current.fieldConfigs.indices.contains(index) ? current.fieldConfigs[index]["fontName"] as? String ?? "Arial" : "Arial", fontSize: editorFontSize > 0 ? editorFontSize : (current.fieldConfigs.indices.contains(index) ? current.fieldConfigs[index]["fontSize"] as? Int ?? 20 : 20), rtl: current.fieldConfigs.indices.contains(index) && current.fieldConfigs[index]["rtl"] as? Bool == true, capitalize: capitalizeEditor)
                            } else {
                            TextEditor(text: Binding(get: { document?.fields[index] ?? "" }, set: { document?.fields[index] = $0; dirty = true }))
                                .frame(minHeight: 110).accessibilityIdentifier("note-field-\(index)")
                                .autocorrectionDisabled().textInputAutocapitalization(capitalizeEditor ? .sentences : .never)
                                .font(.custom(current.fieldConfigs.indices.contains(index) ? current.fieldConfigs[index]["fontName"] as? String ?? "Arial" : "Arial", size: CGFloat(editorFontSize > 0 ? editorFontSize : (current.fieldConfigs.indices.contains(index) ? current.fieldConfigs[index]["fontSize"] as? Int ?? 20 : 20))))
                                .environment(\.layoutDirection, current.fieldConfigs.indices.contains(index) && current.fieldConfigs[index]["rtl"] as? Bool == true ? .rightToLeft : .leftToRight)
                            }
                            Menu {
                                Button(AppText.localized("ファイルから画像・音声を追加"), systemImage: "folder") { mediaField = index; importingMedia = true }
                                Button(AppText.localized("写真ライブラリから追加"), systemImage: "photo.on.rectangle") { mediaField = index; choosingPhoto = true }.accessibilityIdentifier("note-photo-\(index)")
                                Button(AppText.localized("写真を撮影"), systemImage: "camera") { mediaField = index; camera = true }.disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                                Button(AppText.localized("フィールド内の画像を編集"), systemImage: "photo.badge.arrow.down") {
                                    let html = document?.fields[index] ?? ""
                                    selectingImage = FieldImageSelection(field: index, html: html, images: FieldImageReference.extract(html))
                                }.accessibilityIdentifier("note-edit-image-\(index)")
                                Button(AppText.localized("音声を録音"), systemImage: "mic") { mediaField = index; recordingAudio = true }
                            } label: {
                                Label(AppText.localized("添付"), systemImage: "paperclip")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.borderless).accessibilityIdentifier("note-attachment-\(index)")
                            if current.fieldConfigs.indices.contains(index), let description = current.fieldConfigs[index]["description"] as? String, !description.isEmpty { Text(description).font(.footnote).foregroundStyle(.secondary) }
                            } label: { Text(index < current.fieldNames.count ? current.fieldNames[index] : AppText.localized("フィールド \(index + 1)")) }
                        }
                    }
                    if !extraFieldIndices.isEmpty {
                        Section(AppText.localized("このノートタイプにないフィールド")) {
                            Text(AppText.localized("保持している内容を別のフィールドに移すか、空にすると保存できます。"))
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(extraFieldIndices, id: \.self) { index in
                                VStack(alignment: .leading) {
                                    Text(AppText.localized("未割り当てのフィールド \(index + 1)"))
                                    TextEditor(text: Binding(get: { preservedNewFields[index] }, set: { preservedNewFields[index] = $0; dirty = true }))
                                        .frame(minHeight: 90).accessibilityIdentifier("note-unmapped-field-\(index)")
                                }
                            }
                        }
                    }
                    Section {
                        if let incoming = request.incomingMedia {
                            Text(incoming.name).foregroundStyle(.secondary)
                            Button(AppText.localized("受け取ったメディアを挿入")) { insertMedia(incoming.url) }
                                .accessibilityIdentifier("note-insert-received-media")
                        }
                        Button(AppText.localized("保存せずにプレビュー"), systemImage: "eye") { draftPreview = true }.accessibilityIdentifier("note-preview")
                        Button(AppText.localized("このノートを複製"), systemImage: "doc.on.doc") { copied = EditorRequest(deckID: current.deckID, copiedDocument: current) }
                    }
                    Section(AppText.localized("タグ（空白で区切る）")) {
                        TextField(AppText.localized("タグ"), text: Binding(get: { document?.tags ?? "" }, set: { document?.tags = $0; dirty = true }))
                            .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("note-tags")
                    }
                    Section { Text(AppText.localized("フィールドはHTMLを含む元の内容を編集できます。穴埋めは {{c1::内容}} の形式で入力します。"))
                        .font(.footnote).foregroundStyle(.secondary) }
                } else { ProgressView() }
                if busy { ProgressView(AppText.localized("保存中…")) }
            }.accessibilityIdentifier("note-form")
    }
    private var navigationContent: some View {
        editorForm
            .disabled(busy || model.busy)
            .safeAreaInset(edge: .top) {
                VStack {
                    if added { Text(AppText.localized("ノートを追加しました")).foregroundStyle(.green).padding(8).accessibilityIdentifier("note-added") }
                    if let sharedWarning { Text(sharedWarning).foregroundStyle(.orange).padding(8) }
                }
            }
            .studyThemeSurface().navigationTitle(request.isNew ? AppText.localized("ノートを追加") : AppText.localized("ノートを編集"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(request.isNew ? AppText.localized("閉じる") : AppText.localized("キャンセル")) { if dirty { showDiscard = true } else { dismiss() } }.disabled(busy).accessibilityIdentifier("note-close") }
                ToolbarItem(placement: .confirmationAction) { Button(AppText.localized("保存")) { save() }.disabled(document == nil || busy || !extraFieldIndices.isEmpty).accessibilityIdentifier("note-save") }
            }
            .interactiveDismissDisabled(dirty || busy)
            .confirmationDialog(AppText.localized("変更を破棄しますか？"), isPresented: $showDiscard) { Button(AppText.localized("破棄"), role: .destructive) { dismiss() } }
            .alert(AppText.localized("このまま保存しますか？"), isPresented: Binding(get: { fieldWarning != nil }, set: { if !$0 { fieldWarning = nil } })) {
                Button(AppText.localized("保存")) { fieldWarning = nil; save(force: true) }
                Button(AppText.localized("キャンセル"), role: .cancel) { fieldWarning = nil }
            } message: { Text(fieldWarning ?? "") }
    }
    private var schemaContent: some View {
        navigationContent
            .sheet(item: $changingType, onDismiss: {
                guard let current = document else { return }
                busy = true
                Task {
                    defer { busy = false }
                    do {
                        let cards = try await engine.call("NotesService.CardsOfNote", ["nid": current.id])["cids"] as? [String] ?? []
                        let updated = try await engine.noteDocument(cardID: cards.first, noteID: cards.isEmpty ? current.id : nil, typeID: nil, deckID: current.deckID)
                        document = updated
                        typeID = updated.typeID
                        types = try await engine.noteTypes()
                    try Task.checkCancellation()
                        isOcclusion = (try? await engine.call("ImageOcclusionService.GetImageOcclusionFields", ["notetypeId": updated.typeID]))?["fields"] != nil
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
                        guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw EngineError(message: AppText.localized("画像を読み込めませんでした。")) }
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
                        Button(image.source) { openFieldImage(image, selection: selection) }.accessibilityIdentifier("field-image-\(image.id)")
                    }
                    .overlay { if selection.images.isEmpty { ContentUnavailableView(AppText.localized("編集できる画像がありません"), systemImage: "photo") } }
                    .studyThemeSurface().navigationTitle(AppText.localized("画像を選択"))
                    .alert(AppText.localized("画像を開けませんでした"), isPresented: Binding(get: { imageSelectionError != nil }, set: { if !$0 { imageSelectionError = nil } })) {
                        Button(AppText.localized("閉じる"), role: .cancel) { imageSelectionError = nil }
                    } message: { Text(imageSelectionError ?? "") }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button(AppText.localized("キャンセル")) { selectingImage = nil } } }
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
                    let name = try await engine.addMedia(url)
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
            .alert(AppText.localized("処理できませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
            .task {
                guard document == nil else { return }
                busy = true
                defer { busy = false }
                do {
                    types = try await engine.noteTypes()
                    var loaded = try await engine.incomingNoteDocument(request)
                    try Task.checkCancellation()
                    if let source = request.copiedDocument { loaded.fields = source.fields; loaded.tags = source.tags; dirty = true }
                    if let draft = request.initialDraft, request.isNew {
                        for (index, value) in draft.fields.enumerated() where loaded.fields.indices.contains(index) { loaded.fields[index] = value }
                        if let tags = draft.tags { loaded.tags = tags }
                        dirty = draft.fields.contains(where: { !$0.isEmpty }) || draft.tags != nil
                    }
                    typeID = loaded.typeID
                    document = loaded
                    preservedNewFields = loaded.fields
                    isOcclusion = (try? await engine.call("ImageOcclusionService.GetImageOcclusionFields", ["notetypeId": loaded.typeID]))?["fields"] != nil
                    expandFields(loaded)
                    if let file = request.incomingMedia, request.isNew {
                        try await prepareMedia(file.url, field: 0)
                    }
                } catch { self.error = error.localizedDescription }
            }
    }
    private func load(type: String) {
        guard request.isNew, type != document?.typeID else { return }
        let generation = UUID()
        typeLoadGeneration = generation
        busy = true
        Task {
            defer { if typeLoadGeneration == generation { busy = false } }
            do {
                var replacement = try await engine.noteDocument(cardID: nil, typeID: type, deckID: document?.deckID ?? request.deckID)
                guard typeLoadGeneration == generation else { return }
                let retained = NewNoteFields.retaining(document?.fields ?? [], in: preservedNewFields)
                if let previous = document { replacement.tags = previous.tags }
                replacement.fields = NewNoteFields.applying(retained, to: replacement.fields)
                preservedNewFields = retained
                document = replacement
                expandFields(replacement)
                dirty = true
            } catch {
                if typeLoadGeneration == generation {
                    typeID = document?.typeID ?? typeID
                    self.error = error.localizedDescription
                }
            }
        }
    }
    private func expandFields(_ document: NoteDocument) {
        expanded = Set(document.fields.indices.filter { !document.fieldConfigs.indices.contains($0) || document.fieldConfigs[$0]["collapsed"] as? Bool != true })
    }
    private func save(force: Bool = false) {
        guard let document, !busy, extraFieldIndices.isEmpty else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                if !force {
                    let state = try await engine.checkNoteDocument(document)
                    let warnings = ["EMPTY": AppText.localized("最初のフィールドが空です。"), "DUPLICATE": AppText.localized("同じ最初のフィールドを持つノートがあります。"), "MISSING_CLOZE": AppText.localized("穴埋めの指定がありません。"), "NOTETYPE_NOT_CLOZE": AppText.localized("このノートタイプでは穴埋めを生成できません。"), "FIELD_NOT_CLOZE": AppText.localized("穴埋めのフィルターを設定していないフィールドに穴埋めがあります。")]
                    if let warning = warnings[state] { fieldWarning = warning; return }
                }
                try await engine.saveNote(document, isNew: request.isNew)
                if let receipt = request.sharedReceipt {
                    let accepted = await receipt.accept()
                    if !accepted { sharedWarning = AppText.localized("ノートは保存済みですが、共有の受信トレイに元の内容が残っています。") }
                }
                dirty = false
                model.refreshAfterEditing()
                if request.isNew && !closeAfterAdd {
                    var next = try await engine.noteDocument(cardID: nil, typeID: document.typeID, deckID: document.deckID)
                    next.tags = document.tags
                    self.document = next
                    preservedNewFields = next.fields
                    expandFields(next)
                    added = true
                } else { dismiss() }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func openFieldImage(_ reference: FieldImageReference, selection: FieldImageSelection) {
        do {
            let root = engine.media.standardizedFileURL.resolvingSymlinksInPath()
            let url = root.appendingPathComponent(reference.source).standardizedFileURL.resolvingSymlinksInPath()
            guard url.deletingLastPathComponent() == root else { throw EngineError(message: AppText.localized("画像の場所を確認できませんでした。")) }
            let data = try Data(contentsOf: url)
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
                  let image = UIImage(data: data) else { throw EngineError(message: AppText.localized("この画像形式は編集できません。")) }
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
        guard document?.fields.indices.contains(field) == true else { throw EngineError(message: AppText.localized("画像の挿入先が見つかりません。")) }
        busy = true
        defer { busy = false }
        let preferences = try await engine.preferences()
        let asPNG = (preferences["editing"] as? [String: Any])?["pasteImagesAsPng"] as? Bool ?? false
        guard let data = asPNG ? image.pngData() : image.jpegData(compressionQuality: 0.95) else { throw EngineError(message: AppText.localized("写真を変換できませんでした。")) }
        try await insertImageData(data, extension: asPNG ? "png" : "jpg", field: field, replacing: request)
    }
    private func insertImageData(_ data: Data, extension ext: String, field: Int, replacing request: NoteImageEditRequest? = nil) async throws {
        guard document?.fields.indices.contains(field) == true else { throw EngineError(message: AppText.localized("画像の挿入先が見つかりません。")) }
        busy = true
        defer { busy = false }
        if let original = request?.originalField, document?.fields[field] != original {
            throw EngineError(message: AppText.localized("フィールドが変更されています。画像を選び直してください。"))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("photo-" + UUID().uuidString + "." + ext)
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let name = try await engine.addMedia(url)
        let escaped = name.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;")
        if let original = request?.originalField, let range = request?.replacementRange {
            guard document?.fields.indices.contains(field) == true, document?.fields[field] == original else { throw EngineError(message: AppText.localized("フィールドが変更されています。画像を選び直してください。")) }
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
                try await prepareMedia(url, field: field)
            } catch { self.error = error.localizedDescription }
        }
    }
    private func prepareMedia(_ url: URL, field: Int) async throws {
        guard document?.fields.indices.contains(field) == true else {
            throw EngineError(message: AppText.localized("画像の挿入先が見つかりません。"))
        }
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if type?.conforms(to: .image) == true, MediaImagePreparation.canRasterize(url) {
            let data = try BoundedImageFile.read(url, maximumBytes: MediaImagePreparation.maximumEditableFileBytes)
            if let image = UIImage(data: data) {
                pendingImage = NoteImageEditRequest(image: image, field: field, originalData: data, originalExtension: url.pathExtension)
                presentPendingImage()
                return
            }
        }
        let name = try await engine.addMedia(url)
        let encoded = name.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;")
        let content: String
        if type?.conforms(to: .image) == true { content = "<img src=\"\(encoded)\">" }
        else if type?.conforms(to: .movie) == true { content = "<video controls src=\"\(encoded)\"></video>" }
        else { content = "[sound:\(name)]" }
        if document?.fields.indices.contains(field) == true { document?.fields[field] += content; dirty = true }
    }
}
