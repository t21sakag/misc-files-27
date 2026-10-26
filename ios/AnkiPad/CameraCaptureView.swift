import SwiftUI
import UIKit

struct CameraCaptureView: UIViewControllerRepresentable {
    let captured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(captured: captured, dismiss: { dismiss() }) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let captured: (UIImage) -> Void
        let dismiss: () -> Void
        init(captured: @escaping (UIImage) -> Void, dismiss: @escaping () -> Void) { self.captured = captured; self.dismiss = dismiss }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { dismiss() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { captured(image) }
            dismiss()
        }
    }
}
