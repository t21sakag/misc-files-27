import Foundation
import UniformTypeIdentifiers

/// Owns a private copy while an incoming document waits behind editing or sync.
/// The original document is never removed or modified. An import task retains
/// this lease until the engine has finished reading its copy.
final class IncomingImportFile: Identifiable, @unchecked Sendable {
    enum Kind: Equatable, Sendable { case deck, collection, text, image, audio, video }
    struct ImportError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    let id = UUID()
    let name: String
    let url: URL
    let kind: Kind
    let byteCount: Int64
    private let directory: URL

    private init(name: String, url: URL, directory: URL, kind: Kind, byteCount: Int64) {
        self.name = name; self.url = url; self.directory = directory
        self.kind = kind; self.byteCount = byteCount
    }
    deinit { try? FileManager.default.removeItem(at: directory) }

    static func kind(for url: URL) -> Kind? {
        format(for: url)?.kind
    }
    private static func format(for url: URL, typeIdentifier: String? = nil) -> (kind: Kind, ext: String)? {
        guard url.isFileURL else { return nil }
        func documentKind(_ ext: String) -> Kind? {
            switch ext {
            case "apkg": .deck
            case "colpkg": .collection
            case "csv", "tsv", "txt": .text
            default: nil
            }
        }
        let supplied = url.pathExtension.lowercased()
        if let kind = documentKind(supplied) { return (kind, supplied) }
        let declared = supplied.isEmpty ? nil : UTType(filenameExtension: supplied)
        let provided = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        for type in [declared, typeIdentifier.flatMap { UTType($0) }, provided].compactMap({ $0 }) {
            let ext = (type == declared && !supplied.isEmpty ? supplied : type.preferredFilenameExtension) ?? ""
            guard !ext.isEmpty else { continue }
            if let kind = documentKind(ext) { return (kind, ext) }
            if type.conforms(to: .image) { return (.image, ext) }
            if type.conforms(to: .audio) { return (.audio, ext) }
            if type.conforms(to: .movie) { return (.video, ext) }
        }
        return nil
    }
    static func stage(_ source: URL, name displayName: String? = nil, typeIdentifier: String? = nil) throws -> IncomingImportFile {
        guard source.isFileURL else {
            throw ImportError(message: AppText.localized("対応していない取り込みファイルです。"))
        }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<IncomingImportFile, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { readable in
            result = Result {
                guard try readable.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    throw ImportError(message: AppText.localized("通常のファイルを選んでください。"))
                }
                guard let format = Self.format(for: source, typeIdentifier: typeIdentifier) ?? Self.format(for: readable, typeIdentifier: typeIdentifier) else {
                    throw ImportError(message: AppText.localized("対応していない取り込みファイルです。"))
                }
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Received-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                do {
                    // Keep a useful media name, but only as one filename inside
                    // our own directory; never accept path separators from it.
                    let originalName = displayName ?? source.lastPathComponent
                    let sanitized = originalName
                        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\\", with: "_")
                        .replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "\0", with: "_")
                        .components(separatedBy: .controlCharacters).joined()
                    let stem = (sanitized as NSString).deletingPathExtension
                    let candidate = (originalName as NSString).pathExtension.lowercased() == format.ext ? sanitized : stem + "." + format.ext
                    let name = candidate.isEmpty || candidate.utf8.count > 240 ? "source." + format.ext : candidate
                    let local = folder.appendingPathComponent(name, isDirectory: false)
                    try FileManager.default.copyItem(at: readable, to: local)
                    let bytes = (try FileManager.default.attributesOfItem(atPath: local.path)[.size] as? NSNumber)?.int64Value ?? 0
                    return IncomingImportFile(name: originalName, url: local, directory: folder, kind: format.kind, byteCount: bytes)
                } catch {
                    try? FileManager.default.removeItem(at: folder)
                    throw error
                }
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
}

actor IncomingImportStager {
    static let shared = IncomingImportStager()
    func copy(_ source: URL, name: String? = nil, typeIdentifier: String? = nil) throws -> IncomingImportFile {
        try IncomingImportFile.stage(source, name: name, typeIdentifier: typeIdentifier)
    }
}
