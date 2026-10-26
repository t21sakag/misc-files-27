import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Deliver the selected bytes before dismissing, so the next editor can open
/// from the parent sheet's completion without racing the system picker.
struct PhotoSelectionView: UIViewControllerRepresentable {
    let selected: (Data?, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(selected: selected, dismiss: { dismiss() }) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let selected: (Data?, String?) -> Void
        let dismiss: () -> Void
        private var finished = false
        private var loading = false
        init(selected: @escaping (Data?, String?) -> Void, dismiss: @escaping () -> Void) { self.selected = selected; self.dismiss = dismiss }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !finished else { return }
            guard let provider = results.first?.itemProvider else { finished = true; dismiss(); return }
            guard !loading else { return }
            loading = true
            guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
                finished = true; selected(nil, "画像を読み込めませんでした。"); dismiss(); return
            }
            provider.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, error in
                let message = error?.localizedDescription
                Task { @MainActor in
                    guard let self, !self.finished else { return }
                    self.finished = true
                    self.selected(data, message ?? (data == nil ? "画像を読み込めませんでした。" : nil))
                    self.dismiss()
                }
            }
        }
    }
}
