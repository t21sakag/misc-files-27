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
                    Toggle("手書き", isOn: $drawingMode).onChange(of: drawingMode) { _, _ in crop = nil }
                    if drawingMode {
                        Toggle("消しゴム", isOn: $eraser)
                        Button("書き込みを消す") { drawing = PKDrawing() }.disabled(drawing.strokes.isEmpty)
                    }
                }
                Text(drawingMode ? "画像に書き込めます。色やペンはツールパレットで変更できます。" : "画像をドラッグして切り抜く範囲を選べます。") .font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Button("回転", systemImage: "rotate.right") { transform(rotate: true) }.disabled(drawingMode)
                    Button("左右反転", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") { transform(rotate: false) }.disabled(drawingMode)
                    Button("切り抜く", systemImage: "crop") { applyCrop() }.disabled(crop == nil)
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
                }.disabled(saving) }
            }
            .interactiveDismissDisabled(saving)
            .alert("画像を編集できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private func normalized() -> UIImage {
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let bounds = CGRect(origin: .zero, size: size)
            image.draw(in: bounds)
            if !drawing.strokes.isEmpty, canvasSize.width > 0, canvasSize.height > 0 {
                drawing.image(from: CGRect(origin: .zero, size: canvasSize), scale: size.width / canvasSize.width).draw(in: bounds)
            }
        }
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
        let size = rotate ? CGSize(width: source.size.height, height: source.size.width) : source.size
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            if rotate { context.cgContext.rotate(by: .pi / 2) }
            else { context.cgContext.scaleBy(x: -1, y: 1) }
            source.draw(in: CGRect(x: -source.size.width / 2, y: -source.size.height / 2, width: source.size.width, height: source.size.height))
        }
        crop = nil
        drawing = PKDrawing()
        changed = true
    }
    private func applyCrop() {
        guard let crop else { return }
        let source = normalized()
        let rect = CGRect(x: crop.minX * source.size.width, y: crop.minY * source.size.height,
                          width: crop.width * source.size.width, height: crop.height * source.size.height).integral
            .intersection(CGRect(origin: .zero, size: source.size))
        guard rect.width >= 1, rect.height >= 1, let result = source.cgImage?.cropping(to: rect) else {
            error = "切り抜く範囲を広げてください。"; return
        }
        image = UIImage(cgImage: result)
        self.crop = nil
        drawing = PKDrawing()
        changed = true
    }
}
