import Foundation
import UniformTypeIdentifiers

/// NSItemProvider may delete its temporary file as soon as its callback returns.
/// Copy within that callback; the composer owns this lease until publication.
final class ShareProviderFile: @unchecked Sendable {
    let file: SharedIncomingFile
    private let directory: URL
    private init(file: SharedIncomingFile, directory: URL) { self.file = file; self.directory = directory }
    deinit { try? FileManager.default.removeItem(at: directory) }

    static func preferredType(_ provider: NSItemProvider) -> String? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) { return UTType.fileURL.identifier }
        let types = provider.registeredTypeIdentifiers
        if let media = types.first(where: { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .image) || type.conforms(to: .audio) || type.conforms(to: .movie)
        }) { return media }
        // A string/remote URL should remain a text draft, rather than its
        // interchangeable data representation becoming an imported document.
        guard !provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
              !provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else { return nil }
        return types.first { UTType($0)?.conforms(to: .data) == true }
    }
    static func load(_ provider: NSItemProvider, type: String) async throws -> ShareProviderFile {
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            if type == UTType.fileURL.identifier {
                provider.loadItem(forTypeIdentifier: type, options: nil) { value, error in
                    if let error { continuation.resume(throwing: error); return }
                    guard let url = value as? URL, url.isFileURL else { continuation.resume(throwing: CocoaError(.fileReadUnsupportedScheme)); return }
                    continuation.resume(with: Result { try copy(url, name: suggestedName, type: nil) })
                }
            } else {
                provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                    if let error { continuation.resume(throwing: error); return }
                    guard let url else { continuation.resume(throwing: CocoaError(.fileReadUnknown)); return }
                    continuation.resume(with: Result { try copy(url, name: suggestedName, type: type) })
                }
            }
        }
    }
    private static func copy(_ source: URL, name: String?, type: String?) throws -> ShareProviderFile {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<ShareProviderFile, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { readable in
            result = Result {
                guard try readable.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Share-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                do {
                    let local = directory.appendingPathComponent("source")
                    try FileManager.default.copyItem(at: readable, to: local)
                    let declared = type.flatMap { UTType($0) }
                    let original = (name?.isEmpty == false ? name! : source.lastPathComponent)
                    let namedExtension = (original as NSString).pathExtension
                    let ext = !namedExtension.isEmpty ? namedExtension : (!source.pathExtension.isEmpty ? source.pathExtension : declared?.preferredFilenameExtension)
                    let displayName = (original as NSString).pathExtension.isEmpty && ext?.isEmpty == false ? original + "." + ext! : original
                    return ShareProviderFile(file: SharedIncomingFile(url: local, name: displayName, typeIdentifier: type, preferredExtension: ext), directory: directory)
                } catch { try? FileManager.default.removeItem(at: directory); throw error }
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
}
