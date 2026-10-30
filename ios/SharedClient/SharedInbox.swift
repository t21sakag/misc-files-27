import Foundation

struct SharedTextContent: Codable, Equatable, Sendable {
    var subject: String
    var text: String
    var tags: String?
    var isHTML: Bool
    var isEmpty: Bool { subject.isEmpty && text.isEmpty && tags?.isEmpty != false }
}
struct SharedIncomingFile: Sendable {
    let url: URL
    let name: String
    let typeIdentifier: String?
    let preferredExtension: String?
}
struct SharedAttachment: Codable, Equatable, Sendable {
    let storedName: String
    let originalName: String
    let typeIdentifier: String?
    let bytes: Int64
}
struct SharedTransfer: Codable, Identifiable, Sendable {
    let version: Int
    let id: UUID
    let createdAt: Date
    let text: SharedTextContent?
    let attachments: [SharedAttachment]
}
struct SharedInboxEntry: Identifiable, Sendable {
    let transfer: SharedTransfer
    let directory: URL
    var id: UUID { transfer.id }
    func file(_ attachment: SharedAttachment) -> URL { directory.appendingPathComponent(attachment.storedName) }
}
struct SharedInboxScan: Sendable {
    var entries: [SharedInboxEntry] = []
    var invalid: [UUID] = []
}

/// Immutable packages become visible with one rename. Until explicit acceptance
/// or discard they remain ready across extension/app termination. The collection
/// database and credentials never enter this directory.
struct SharedInbox: Sendable {
    enum InboxError: Error { case invalidInput, invalidManifest, unsupportedVersion, changedAttachment }
    static let maximumManifestBytes = 16 * 1024 * 1024
    let root: URL
    private var manager: FileManager { .default }
    private func package(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func regularFile(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return values.isRegularFile == true && values.isSymbolicLink != true
    }
    private func directory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values.isDirectory == true && values.isSymbolicLink != true
    }
    func publish(text: SharedTextContent?, files: [SharedIncomingFile]) throws -> UUID {
        let text = text.flatMap { $0.isEmpty ? nil : $0 }
        guard text != nil || !files.isEmpty else { throw InboxError.invalidInput }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID()
        let staging = root.appendingPathComponent(".writing-" + id.uuidString, isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        var committed = false
        defer { if !committed { try? manager.removeItem(at: staging) } }
        var attachments: [SharedAttachment] = []
        for file in files {
            guard file.url.isFileURL else { throw InboxError.invalidInput }
            let source = file.url.resolvingSymlinksInPath()
            guard try regularFile(source) else { throw InboxError.invalidInput }
            let proposed = file.preferredExtension ?? (file.name as NSString).pathExtension
            let ext = proposed.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
            let name = UUID().uuidString + (ext.isEmpty || ext.count > 24 ? "" : "." + ext)
            let destination = staging.appendingPathComponent(name)
            try manager.copyItem(at: source, to: destination)
            let bytes = (try manager.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
            attachments.append(SharedAttachment(storedName: name, originalName: file.name,
                                                typeIdentifier: file.typeIdentifier, bytes: bytes))
        }
        let transfer = SharedTransfer(version: 1, id: id, createdAt: Date(), text: text, attachments: attachments)
        let data = try JSONEncoder().encode(transfer)
        guard data.count <= Self.maximumManifestBytes else { throw InboxError.invalidInput }
        try data.write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
        var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
        var folder = staging; try folder.setResourceValues(excluded)
        try manager.moveItem(at: staging, to: package(id))
        committed = true
        return id
    }
    func read(_ id: UUID) throws -> SharedInboxEntry {
        let folder = package(id)
        guard try directory(folder) else { throw InboxError.invalidManifest }
        let manifest = folder.appendingPathComponent("manifest.json")
        guard try regularFile(manifest),
              (try manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= Self.maximumManifestBytes else { throw InboxError.invalidManifest }
        let transfer = try JSONDecoder().decode(SharedTransfer.self, from: Data(contentsOf: manifest))
        guard transfer.version == 1 else { throw InboxError.unsupportedVersion }
        guard transfer.id == id, transfer.text != nil || !transfer.attachments.isEmpty else { throw InboxError.invalidManifest }
        var names = Set<String>()
        for file in transfer.attachments {
            guard !file.storedName.isEmpty, file.storedName != ".", file.storedName != "..",
                  !file.storedName.contains("/"), !file.storedName.contains("\\"), !file.storedName.contains("\0"),
                  file.storedName != "manifest.json", file.storedName != ".consumed", file.bytes >= 0,
                  names.insert(file.storedName).inserted else { throw InboxError.invalidManifest }
            let url = folder.appendingPathComponent(file.storedName)
            guard try regularFile(url),
                  (try manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value == file.bytes else { throw InboxError.changedAttachment }
        }
        return SharedInboxEntry(transfer: transfer, directory: folder)
    }
    func scan() throws -> SharedInboxScan {
        guard manager.fileExists(atPath: root.path) else { return SharedInboxScan() }
        var result = SharedInboxScan()
        for folder in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            guard !manager.fileExists(atPath: folder.appendingPathComponent(".consumed").path) else { continue }
            do { result.entries.append(try read(id)) }
            catch { result.invalid.append(id) }
        }
        result.entries.sort {
            if $0.transfer.createdAt == $1.transfer.createdAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.transfer.createdAt < $1.transfer.createdAt
        }
        return result
    }
    /// Mark first, then remove. A failed cleanup cannot resurrect a completed
    /// share on the next launch. Only this exact UUID's directory is touched.
    func finish(_ id: UUID) throws {
        let folder = package(id)
        guard manager.fileExists(atPath: folder.path) else { return }
        guard try directory(folder) else { throw InboxError.invalidManifest }
        try Data().write(to: folder.appendingPathComponent(".consumed"), options: .atomic)
        try? manager.removeItem(at: folder)
    }
}
