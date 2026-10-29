import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Deliver the selected bytes before dismissing, so the next editor can open
/// from the parent sheet's completion without racing the system picker.
struct PhotoSelectionView: UIViewControllerRepresentable {
    var maximumBytes: Int? = nil
    let selected: (Data?, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(maximumBytes: maximumBytes, selected: selected, dismiss: { dismiss() }) }
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
        let maximumBytes: Int?
        let dismiss: () -> Void
        private var finished = false
        private var loading = false
        init(maximumBytes: Int?, selected: @escaping (Data?, String?) -> Void, dismiss: @escaping () -> Void) {
            self.maximumBytes = maximumBytes; self.selected = selected; self.dismiss = dismiss
        }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !finished else { return }
            guard let provider = results.first?.itemProvider else { finished = true; dismiss(); return }
            guard !loading else { return }
            loading = true
            guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
                finished = true; selected(nil, AppText.localized("画像を読み込めませんでした。")); dismiss(); return
            }
            if let maximumBytes {
                // This URL is valid only during the provider callback. Copy the
                // bounded bytes here before returning; decoding happens later.
                provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, error in
                    let result: Result<Data, Error>
                    do {
                        guard let url else { throw error ?? CocoaError(.fileReadUnknown) }
                        result = .success(try BoundedImageFile.read(url, maximumBytes: maximumBytes))
                    } catch { result = .failure(error) }
                    Task { @MainActor in
                        guard let self, !self.finished else { return }
                        self.finished = true
                        switch result {
                        case .success(let data): self.selected(data, nil)
                        case .failure(let error): self.selected(nil, error.localizedDescription)
                        }
                        self.dismiss()
                    }
                }
                return
            }
            provider.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, error in
                let message = error?.localizedDescription
                Task { @MainActor in
                    guard let self, !self.finished else { return }
                    self.finished = true
                    self.selected(data, message ?? (data == nil ? AppText.localized("画像を読み込めませんでした。") : nil))
                    self.dismiss()
                }
            }
        }
    }
}
