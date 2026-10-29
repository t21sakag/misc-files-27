import Foundation

/// Owns a private copy while an incoming document waits behind editing or sync.
/// The original document is never removed or modified. An import task retains
/// this lease until the engine has finished reading its copy.
final class IncomingImportFile: Identifiable, @unchecked Sendable {
    enum Kind: Equatable, Sendable { case deck, collection, text }
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
        guard url.isFileURL else { return nil }
        switch url.pathExtension.lowercased() {
        case "apkg": return .deck
        case "colpkg": return .collection
        case "csv", "tsv", "txt": return .text
        default: return nil
        }
    }
    static func stage(_ source: URL) throws -> IncomingImportFile {
        guard let kind = kind(for: source) else {
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
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Received-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                do {
                    let local = folder.appendingPathComponent("source." + source.pathExtension.lowercased())
                    try FileManager.default.copyItem(at: readable, to: local)
                    let bytes = (try FileManager.default.attributesOfItem(atPath: local.path)[.size] as? NSNumber)?.int64Value ?? 0
                    return IncomingImportFile(name: source.lastPathComponent, url: local, directory: folder, kind: kind, byteCount: bytes)
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
    func copy(_ source: URL) throws -> IncomingImportFile { try IncomingImportFile.stage(source) }
}
