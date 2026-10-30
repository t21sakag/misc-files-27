import Foundation

@main struct IncomingImportFileSmoke {
    static func main() throws {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent("IncomingFileSmoke-" + UUID().uuidString)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: folder) }
        let cases: [(String, IncomingImportFile.Kind)] = [
            ("デッキ.APKG", .deck), ("backup.colpkg", .collection), ("table.csv", .text),
            ("table.tsv", .text), ("body.txt", .text), ("still.png", .image),
            ("animated.gif", .image), ("voice.mp3", .audio), ("movie.mp4", .video)
        ]
        for (name, kind) in cases {
            let source = folder.appendingPathComponent(name)
            let original = Data(("Original bytes: " + name).utf8)
            try original.write(to: source)
            precondition(IncomingImportFile.kind(for: source) == kind, name)
            var lease: IncomingImportFile? = try IncomingImportFile.stage(source)
            let copy = lease!.url, ownedDirectory = copy.deletingLastPathComponent()
            precondition(copy != source && ownedDirectory != folder)
            precondition(lease!.name == name && lease!.kind == kind && lease!.byteCount == original.count)
            let copiedBytes = try Data(contentsOf: copy)
            precondition(copiedBytes == original)
            let sourceBytes = try Data(contentsOf: source)
            precondition(sourceBytes == original)
            // An asynchronous consumer keeps its independent reference even if
            // the confirmation sheet releases its copy of the lease.
            var consumer = [lease!]
            lease = nil
            precondition(manager.fileExists(atPath: copy.path))
            try manager.removeItem(at: source)
            let retainedBytes = try Data(contentsOf: consumer[0].url)
            precondition(retainedBytes == original)
            consumer.removeAll()
            precondition(!manager.fileExists(atPath: ownedDirectory.path), name)
            precondition(manager.fileExists(atPath: folder.path))
        }
        let sharedMedia = folder.appendingPathComponent(UUID().uuidString)
        try Data("Shared bytes".utf8).write(to: sharedMedia)
        let staged = try IncomingImportFile.stage(sharedMedia, name: "元の画像.png", typeIdentifier: "public.png")
        precondition(staged.name == "元の画像.png" && staged.kind == .image && staged.url.lastPathComponent == "元の画像.png")
        let stagedData = try Data(contentsOf: staged.url)
        precondition(stagedData == Data("Shared bytes".utf8))
        let unsupported = folder.appendingPathComponent("unrecognized.zzztest")
        try Data([1, 2, 3]).write(to: unsupported)
        do { _ = try IncomingImportFile.stage(unsupported); preconditionFailure("accepted unsupported document") }
        catch { precondition(manager.fileExists(atPath: unsupported.path)) }
        let directory = folder.appendingPathComponent("directory.apkg")
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        do { _ = try IncomingImportFile.stage(directory); preconditionFailure("accepted directory") }
        catch { precondition(manager.fileExists(atPath: directory.path)) }
        precondition(IncomingImportFile.kind(for: URL(string: "https://invalid.example/file.apkg")!) == nil)
        print("PASS: document/media classification, exact private copies, original preservation, independent lease lifetime, cleanup and rejection of directories/unsupported input")
    }
}
