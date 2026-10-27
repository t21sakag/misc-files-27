import SwiftUI
import UIKit
import PencilKit

struct NoteImageEditRequest: Identifiable {
    let id = UUID()
    let image: UIImage
    let field: Int
    var originalData: Data? = nil
    var originalExtension: String? = nil
    var originalField: String? = nil
    var replacementRange: NSRange? = nil
}

struct NoteImageEditorView: View {
    let request: NoteImageEditRequest
    let insert: (UIImage, Bool) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage
    @State private var crop: CGRect?
    @State private var saving = false
    @State private var changed = false
    @State private var error: String?
    @State private var drawing = PKDrawing()
    @State private var drawingMode = false
    @State private var eraser = false
    @State private var canvasSize = CGSize.zero
    init(request: NoteImageEditRequest, insert: @escaping (UIImage, Bool) async throws -> Void) {
        self.request = request
        self.insert = insert
        _image = State(initialValue: request.image)
    }
    var body: some View {
        NavigationStack {
            VStack {
                GeometryReader { geometry in
                    let factor = min(geometry.size.width / image.size.width, geometry.size.height / image.size.height)
                    let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
                            .accessibilityLabel("編集する画像").accessibilityIdentifier("image-editor-image")
                            .accessibilityValue("\(Int(image.size.width * image.scale)) × \(Int(image.size.height * image.scale)) ピクセル")
                        if drawingMode {
                            WhiteboardCanvas(drawing: $drawing, eraser: eraser)
                                .frame(width: size.width, height: size.height)
                        } else if !drawing.strokes.isEmpty, canvasSize.width > 0, canvasSize.height > 0 {
                            Image(uiImage: drawing.image(from: CGRect(origin: .zero, size: canvasSize), scale: 1))
                                .resizable().frame(width: size.width, height: size.height).allowsHitTesting(false)
                        }
                        if let crop {
                            Rectangle().fill(.yellow.opacity(0.15)).overlay(Rectangle().stroke(.yellow, lineWidth: 2))
                                .frame(width: crop.width * size.width, height: crop.height * size.height)
                                .offset(x: crop.minX * size.width, y: crop.minY * size.height)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 8).onChanged { value in
                        guard !drawingMode, size.width > 0, size.height > 0 else { return }
                        let start = CGPoint(x: min(1, max(0, value.startLocation.x / size.width)), y: min(1, max(0, value.startLocation.y / size.height)))
                        let end = CGPoint(x: min(1, max(0, value.location.x / size.width)), y: min(1, max(0, value.location.y / size.height)))
                        crop = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
                    }, including: drawingMode ? .subviews : .all)
                    .onAppear { resizeDrawing(to: size) }
                    .onChange(of: size) { _, next in resizeDrawing(to: next) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("編集する画像")
                    .accessibilityHint(drawingMode ? "指またはApple Pencilで画像に書き込めます。" : "ドラッグして切り抜く範囲を選びます。")
                }
                HStack {
                    Toggle("手書き", isOn: $drawingMode).accessibilityIdentifier("image-editor-drawing").onChange(of: drawingMode) { _, _ in crop = nil }
                    if drawingMode {
                        Toggle("消しゴム", isOn: $eraser)
                        Button("書き込みを消す") { drawing = PKDrawing() }.disabled(drawing.strokes.isEmpty)
                    }
                }
                Text(drawingMode ? "画像に書き込めます。色やペンはツールパレットで変更できます。" : "画像をドラッグして切り抜く範囲を選べます。") .font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Button("回転", systemImage: "rotate.right") { transform(rotate: true) }.accessibilityIdentifier("image-editor-rotate").disabled(drawingMode)
                    Button("左右反転", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") { transform(rotate: false) }.accessibilityIdentifier("image-editor-mirror").disabled(drawingMode)
                    Button("切り抜く", systemImage: "crop") { applyCrop() }.accessibilityIdentifier("image-editor-crop").disabled(crop == nil)
                    Button("元に戻す") { image = request.image; crop = nil; changed = false; drawing = PKDrawing(); drawingMode = false }
                }.buttonStyle(.bordered)
            }
            .padding().disabled(saving)
            .navigationTitle("画像を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("挿入") {
                    saving = true
                    Task {
                        defer { saving = false }
                        do { try await insert(drawing.strokes.isEmpty ? image : normalized(), changed || !drawing.strokes.isEmpty); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(saving).accessibilityIdentifier("image-editor-insert") }
            }
            .interactiveDismissDisabled(saving)
            .alert("画像を編集できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private func normalized() -> UIImage {
        NoteImageRendering.normalized(image, drawing: drawing, canvasSize: canvasSize)
    }

    private func resizeDrawing(to next: CGSize) {
        guard next.width > 0, next.height > 0 else { return }
        if canvasSize.width > 0, canvasSize.height > 0, !drawing.strokes.isEmpty {
            drawing = drawing.transformed(using: CGAffineTransform(scaleX: next.width / canvasSize.width, y: next.height / canvasSize.height))
        }
        canvasSize = next
    }
    private func transform(rotate: Bool) {
        let source = normalized()
        image = NoteImageRendering.transformed(source, rotate: rotate)
        crop = nil
        drawing = PKDrawing()
        changed = true
    }
    private func applyCrop() {
        guard let crop else { return }
        let source = normalized()
        guard let result = NoteImageRendering.cropped(source, unitRect: crop) else {
            error = "切り抜く範囲を広げてください。"; return
        }
        image = result
        self.crop = nil
        drawing = PKDrawing()
        changed = true
    }
}
