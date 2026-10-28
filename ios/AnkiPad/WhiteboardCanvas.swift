import SwiftUI
import PencilKit

struct WhiteboardCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var pencilOnly = false
    var eraser = false
    var penColor: UIColor?
    var toolPickerVisible = true
    var penColorChanged: (UIColor) -> Void = { _ in }
    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        canvas.tool = Self.pen(penColor)
        canvas.delegate = context.coordinator
        canvas.isAccessibilityElement = true
        canvas.accessibilityLabel = "手書きキャンバス"
        canvas.accessibilityIdentifier = "whiteboard"
        canvas.drawing = drawing
        canvas.accessibilityValue = "\(drawing.strokes.count)本の描線"
        context.coordinator.canvas = canvas
        context.coordinator.penColorChanged = penColorChanged
        context.coordinator.toolPickerVisible = toolPickerVisible
        DispatchQueue.main.async {
            let picker = PKToolPicker()
            context.coordinator.picker = picker
            picker.selectedTool = canvas.tool
            picker.addObserver(canvas)
            picker.addObserver(context.coordinator)
            picker.setVisible(context.coordinator.toolPickerVisible, forFirstResponder: canvas)
            canvas.becomeFirstResponder()
        }
        return canvas
    }
    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        let coordinator = context.coordinator
        coordinator.drawing = $drawing
        coordinator.penColorChanged = penColorChanged
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        canvas.accessibilityValue = "\(drawing.strokes.count)本の描線"
        if coordinator.eraser != eraser {
            if eraser { coordinator.previousTool = canvas.tool; canvas.tool = PKEraserTool(.vector) }
            else { canvas.tool = coordinator.previousTool ?? Self.pen(penColor) }
            coordinator.eraser = eraser
        }
        if coordinator.toolPickerVisible != toolPickerVisible {
            coordinator.toolPickerVisible = toolPickerVisible
            coordinator.picker?.setVisible(toolPickerVisible, forFirstResponder: canvas)
        }
        if canvas.drawing.dataRepresentation() != drawing.dataRepresentation() { canvas.drawing = drawing }
    }
    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.picker?.setVisible(false, forFirstResponder: canvas)
        coordinator.picker?.removeObserver(canvas)
        coordinator.picker?.removeObserver(coordinator)
        canvas.resignFirstResponder()
    }
    static func pen(_ color: UIColor?) -> PKInkingTool { PKInkingTool(.pen, color: color ?? .systemBlue, width: 3) }
    final class Coordinator: NSObject, PKCanvasViewDelegate, PKToolPickerObserver {
        var drawing: Binding<PKDrawing>
        var picker: PKToolPicker?
        var previousTool: PKTool?
        var eraser = false
        var toolPickerVisible = true
        var penColorChanged: (UIColor) -> Void = { _ in }
        weak var canvas: PKCanvasView?
        init(drawing: Binding<PKDrawing>) { self.drawing = drawing }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { drawing.wrappedValue = canvasView.drawing }
        func toolPickerSelectedToolDidChange(_ toolPicker: PKToolPicker) {
            if let ink = toolPicker.selectedTool as? PKInkingTool { penColorChanged(ink.color) }
        }
    }
}

extension UIColor {
    var whiteboardRGBA: UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(1, max(0, value)) * 255).rounded()) }
        return byte(red) << 24 | byte(green) << 16 | byte(blue) << 8 | byte(alpha)
    }
    convenience init(whiteboardRGBA value: UInt32) {
        func part(_ shift: UInt32) -> CGFloat { CGFloat((value >> shift) & 0xFF) / 255 }
        self.init(red: part(24), green: part(16), blue: part(8), alpha: part(0))
    }
}
