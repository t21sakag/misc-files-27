import Foundation

@main struct BackupExportSmoke {
    static func main() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? files.removeItem(at: root) }
        let backups = root.appendingPathComponent("profile/backups")
        let temporary = root.appendingPathComponent("temporary")
        try files.createDirectory(at: backups, withIntermediateDirectories: true)
        let source = backups.appendingPathComponent("backup-original.colpkg")
        let original = Data([0x50, 0x4b, 0, 1, 255])
        try original.write(to: source)
        let exported = try BackupExport.prepare(source, backupFolder: backups, temporaryFolder: temporary)
        precondition(exported.url.lastPathComponent == source.lastPathComponent)
        let originalAfterExport = try Data(contentsOf: source)
        let snapshot = try Data(contentsOf: exported.url)
        precondition(originalAfterExport == original && snapshot == original)
        // A subsequent backup rotation must not invalidate a destination's read.
        try files.removeItem(at: source)
        let afterRotation = try Data(contentsOf: exported.url)
        precondition(afterRotation == original)
        exported.removeTemporaryCopy()
        precondition(!files.fileExists(atPath: exported.url.path))
        let other = root.appendingPathComponent("other.colpkg")
        try original.write(to: other)
        do {
            _ = try BackupExport.prepare(other, backupFolder: backups, temporaryFolder: temporary)
            fatalError("Another profile's file must not be exported")
        } catch is CocoaError { }
        let link = backups.appendingPathComponent("link.colpkg")
        try files.createSymbolicLink(at: link, withDestinationURL: other)
        do {
            _ = try BackupExport.prepare(link, backupFolder: backups, temporaryFolder: temporary)
            fatalError("A symlink must not expose a file outside backups")
        } catch is CocoaError { }
        print("PASS: original-name byte-identical snapshot, rotation-safe read, cleanup and profile/symlink isolation")
    }
}
