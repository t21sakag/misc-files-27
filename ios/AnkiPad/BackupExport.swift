import Foundation

/// A share operation owns a copy, so backup rotation or restoration cannot
/// remove the file while Files or another share destination is reading it.
struct BackupExport: Identifiable {
    let url: URL
    var id: URL { url }

    static func prepare(_ source: URL, backupFolder: URL, temporaryFolder: URL = FileManager.default.temporaryDirectory) throws -> BackupExport {
        let files = FileManager.default
        let folder = backupFolder.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = source.standardizedFileURL
        let attributes = try candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard candidate.deletingLastPathComponent().resolvingSymlinksInPath() == folder,
              candidate.pathExtension.lowercased() == "colpkg",
              attributes.isRegularFile == true, attributes.isSymbolicLink != true else {
            throw CocoaError(.fileReadNoPermission)
        }
        let destination = temporaryFolder.appendingPathComponent("backup-share-" + UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: destination, withIntermediateDirectories: true)
        let output = destination.appendingPathComponent(candidate.lastPathComponent)
        do { try files.copyItem(at: candidate, to: output) }
        catch { try? files.removeItem(at: destination); throw error }
        return BackupExport(url: output)
    }

    func removeTemporaryCopy() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}
