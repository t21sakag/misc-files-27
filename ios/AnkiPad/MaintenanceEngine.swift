import Foundation

struct CollectionBackup: Identifiable {
    let url: URL
    let date: Date
    let size: Int64
    var fileName: String { url.lastPathComponent }
    var id: String { fileName }
}
extension Engine {
    func preferences() throws -> [String: Any] { try call("ConfigService.GetPreferences") }
    func savePreferences(_ values: [String: Any]) throws { _ = try call("ConfigService.SetPreferences", values) }
    func backups() throws -> [CollectionBackup] {
        let folder = root.appendingPathComponent("backups", isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        return urls.filter { $0.pathExtension == "colpkg" }.map { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return CollectionBackup(url: url, date: values?.contentModificationDate ?? .distantPast, size: Int64(values?.fileSize ?? 0))
        }.sorted { $0.date > $1.date }
    }
    func checkDatabase() async throws -> [String] {
        try backup()
        return try await longCall("CollectionService.CheckDatabase", [:])["problems"] as? [String] ?? []
    }
    func checkMedia() async throws -> [String: Any] { try await longCall("MediaService.CheckMedia", [:]) }
    func trashMedia(_ names: [String]) throws { _ = try call("MediaService.TrashMediaFiles", ["fnames": names]) }
    func restoreMediaTrash() throws { _ = try call("MediaService.RestoreTrash") }
    func emptyMediaTrash() throws { _ = try call("MediaService.EmptyTrash") }
    func prepareImport(_ url: URL) throws -> URL {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try backup()
        let folder = root.appendingPathComponent("imports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let local = folder.appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
        try FileManager.default.copyItem(at: url, to: local)
        return local
    }
}
