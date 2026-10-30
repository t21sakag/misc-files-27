import Foundation
import UniformTypeIdentifiers

@main struct SharedProviderFileSmoke {
    static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("ProviderSmoke-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        let source = root.appendingPathComponent("document.apkg")
        let bytes = Data("Synthetic provider bytes".utf8)
        try bytes.write(to: source)
        let fileProvider = NSItemProvider(item: source as NSURL, typeIdentifier: UTType.fileURL.identifier)
        fileProvider.suggestedName = "original.apkg"
        precondition(ShareProviderFile.preferredType(fileProvider) == UTType.fileURL.identifier)
        var file: ShareProviderFile? = try await ShareProviderFile.load(fileProvider, type: UTType.fileURL.identifier)
        let fileCopy = file!.file.url
        precondition(file!.file.name == "original.apkg")
        precondition(manager.fileExists(atPath: source.path))
        try manager.removeItem(at: source)
        let received = try Data(contentsOf: fileCopy)
        precondition(received == bytes)
        let inbox = SharedInbox(root: root.appendingPathComponent("inbox"))
        let id = try inbox.publish(text: nil, files: [file!.file])
        file = nil
        precondition(!manager.fileExists(atPath: fileCopy.path))
        let entry = try inbox.read(id)
        precondition(entry.transfer.attachments[0].originalName == "original.apkg")
        precondition(entry.transfer.attachments[0].storedName.hasSuffix(".apkg"))
        let persisted = try Data(contentsOf: entry.file(entry.transfer.attachments[0]))
        precondition(persisted == bytes)
        // A data/file representation is obtained and copied inside the callback,
        // without loading a whole image/audio/video into the extension heap.
        let image = root.appendingPathComponent("source.png")
        try bytes.write(to: image)
        let mediaProvider = NSItemProvider()
        mediaProvider.suggestedName = "shared-image"
        mediaProvider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
            completion(image, false, nil)
            return nil
        }
        precondition(ShareProviderFile.preferredType(mediaProvider) == UTType.png.identifier)
        let media = try await ShareProviderFile.load(mediaProvider, type: UTType.png.identifier)
        try manager.removeItem(at: image)
        let copied = try Data(contentsOf: media.file.url)
        precondition(copied == bytes && media.file.name == "shared-image.png")
        let text = NSItemProvider(item: "plain text" as NSString, typeIdentifier: UTType.plainText.identifier)
        precondition(ShareProviderFile.preferredType(text) == nil)
        let link = NSItemProvider(item: URL(string: "https://example.invalid/page")! as NSURL, typeIdentifier: UTType.url.identifier)
        precondition(ShareProviderFile.preferredType(link) == nil)
        print("PASS: real file-URL/media NSItemProviders, original naming, independent copied lifetime, source removal, durable publication and plain-text/remote-URL routing")
    }
}
