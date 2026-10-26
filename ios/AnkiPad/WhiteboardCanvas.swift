import SwiftUI
import PencilKit

struct WhiteboardCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var pencilOnly = false
    var eraser = false
    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        canvas.tool = PKInkingTool(.pen, color: .systemBlue, width: 3)
        canvas.delegate = context.coordinator
        canvas.isAccessibilityElement = true
        canvas.accessibilityLabel = "手書きキャンバス"
        canvas.accessibilityIdentifier = "whiteboard"
        canvas.drawing = drawing
        context.coordinator.canvas = canvas
        DispatchQueue.main.async {
            let picker = PKToolPicker()
            context.coordinator.picker = picker
            picker.addObserver(canvas)
            picker.setVisible(true, forFirstResponder: canvas)
            canvas.becomeFirstResponder()
        }
        return canvas
    }
    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.drawing = $drawing
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        if context.coordinator.eraser != eraser {
            if eraser { context.coordinator.previousTool = canvas.tool; canvas.tool = PKEraserTool(.vector) }
            else { canvas.tool = context.coordinator.previousTool ?? PKInkingTool(.pen, color: .systemBlue, width: 3) }
            context.coordinator.eraser = eraser
        }
        if canvas.drawing.dataRepresentation() != drawing.dataRepresentation() { canvas.drawing = drawing }
    }
    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.picker?.setVisible(false, forFirstResponder: canvas)
        coordinator.picker?.removeObserver(canvas)
        canvas.resignFirstResponder()
    }
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>
        var picker: PKToolPicker?
        var previousTool: PKTool?
        var eraser = false
        weak var canvas: PKCanvasView?
        init(drawing: Binding<PKDrawing>) { self.drawing = drawing }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { drawing.wrappedValue = canvasView.drawing }
    }
}
