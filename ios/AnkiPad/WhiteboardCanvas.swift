import SwiftUI
import PencilKit

struct WhiteboardCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var pencilOnly = false
    var eraser = false
    var penColor: UIColor?
    var penWidth: CGFloat = 3
    var toolPickerVisible = true
    var penColorChanged: (UIColor) -> Void = { _ in }
    var penWidthChanged: (CGFloat) -> Void = { _ in }
    var userDrawingChanged: () -> Void = {}
    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        canvas.tool = Self.pen(penColor, width: penWidth)
        canvas.delegate = context.coordinator
        canvas.isAccessibilityElement = true
        canvas.accessibilityLabel = AppText.localized("手書きキャンバス")
        canvas.accessibilityIdentifier = "whiteboard"
        canvas.drawing = drawing
        canvas.accessibilityValue = AppText.localized("\(drawing.strokes.count)本の描線")
        context.coordinator.canvas = canvas
        context.coordinator.penColorRGBA = penColor?.whiteboardRGBA
        context.coordinator.penWidth = penWidth
        context.coordinator.penColorChanged = penColorChanged
        context.coordinator.penWidthChanged = penWidthChanged
        context.coordinator.userDrawingChanged = userDrawingChanged
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
        coordinator.penWidthChanged = penWidthChanged
        coordinator.userDrawingChanged = userDrawingChanged
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        canvas.accessibilityValue = AppText.localized("\(drawing.strokes.count)本の描線")
        let nextColorRGBA = penColor?.whiteboardRGBA
        let penStyleChanged = coordinator.penColorRGBA != nextColorRGBA || abs(coordinator.penWidth - penWidth) > 0.05
        coordinator.penColorRGBA = nextColorRGBA
        coordinator.penWidth = penWidth
        if coordinator.eraser != eraser {
            if eraser { coordinator.previousTool = canvas.tool; canvas.tool = PKEraserTool(.vector) }
            else { canvas.tool = Self.pen(penColor, width: penWidth) }
            coordinator.eraser = eraser
        } else if !eraser && penStyleChanged {
            let updatedPen = Self.pen(penColor, width: penWidth)
            canvas.tool = updatedPen
            coordinator.picker?.selectedTool = updatedPen
        }
        if coordinator.toolPickerVisible != toolPickerVisible {
            coordinator.toolPickerVisible = toolPickerVisible
            coordinator.picker?.setVisible(toolPickerVisible, forFirstResponder: canvas)
        }
        if canvas.drawing.dataRepresentation() != drawing.dataRepresentation() {
            coordinator.suppressUserCallback = true
            canvas.drawing = drawing
            coordinator.suppressUserCallback = false
        }
    }
    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.picker?.setVisible(false, forFirstResponder: canvas)
        coordinator.picker?.removeObserver(canvas)
        coordinator.picker?.removeObserver(coordinator)
        canvas.resignFirstResponder()
    }
    static func pen(_ color: UIColor?, width: CGFloat = 3) -> PKInkingTool {
        PKInkingTool(.pen, color: color ?? .systemBlue, width: min(40, max(1, width)))
    }
    final class Coordinator: NSObject, PKCanvasViewDelegate, PKToolPickerObserver {
        var drawing: Binding<PKDrawing>
        var picker: PKToolPicker?
        var previousTool: PKTool?
        var eraser = false
        var penColorRGBA: UInt32?
        var penWidth: CGFloat = 3
        var toolPickerVisible = true
        var suppressUserCallback = false
        var penColorChanged: (UIColor) -> Void = { _ in }
        var penWidthChanged: (CGFloat) -> Void = { _ in }
        var userDrawingChanged: () -> Void = {}
        weak var canvas: PKCanvasView?
        init(drawing: Binding<PKDrawing>) { self.drawing = drawing }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            if !suppressUserCallback { userDrawingChanged() }
            drawing.wrappedValue = canvasView.drawing
        }
        func toolPickerSelectedToolDidChange(_ toolPicker: PKToolPicker) {
            if let ink = toolPicker.selectedTool as? PKInkingTool {
                penColorRGBA = ink.color.whiteboardRGBA
                penWidth = ink.width
                penColorChanged(ink.color)
                penWidthChanged(ink.width)
            }
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
