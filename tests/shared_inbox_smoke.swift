import Foundation

@main struct SharedInboxSmoke {
    static func main() throws {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent("SharedInboxSmoke-" + UUID().uuidString)
        try manager.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: base) }
        let source = base.appendingPathComponent("original.jpg"), bytes = Data("original content 日本語".utf8)
        try bytes.write(to: source)
        let inbox = SharedInbox(root: base.appendingPathComponent("inbox"))
        let text = SharedTextContent(subject: "件名", text: "本文\n<&>", tags: "one 日本語", isHTML: false)
        let file = SharedIncomingFile(url: source, name: "original.jpg", typeIdentifier: "public.jpeg", preferredExtension: "jpg")
        let id = try inbox.publish(text: text, files: [file, file])
        let entry = try inbox.read(id)
        precondition(entry.transfer.text == text && entry.transfer.attachments.count == 2)
        precondition(Set(entry.transfer.attachments.map(\.storedName)).count == 2)
        let initialNames = try manager.contentsOfDirectory(atPath: inbox.root.path)
        precondition(initialNames.count == 1)
        let original = try Data(contentsOf: source)
        precondition(original == bytes)
        try manager.removeItem(at: source)
        let reopened = SharedInbox(root: inbox.root)
        let restored = try reopened.read(id)
        for attachment in restored.transfer.attachments {
            let copied = try Data(contentsOf: restored.file(attachment))
            precondition(copied == bytes && attachment.bytes == bytes.count)
        }
        let hidden = inbox.root.appendingPathComponent(".writing-abandoned", isDirectory: true)
        try manager.createDirectory(at: hidden, withIntermediateDirectories: false)
        let scan = try reopened.scan()
        precondition(scan.entries.map(\.id) == [id] && scan.invalid.isEmpty)
        // A failed publication must leave no visible request or private partial.
        do {
            _ = try inbox.publish(text: nil, files: [file])
            preconditionFailure("Missing source unexpectedly accepted")
        } catch {}
        let namesAfterFailure = try manager.contentsOfDirectory(atPath: inbox.root.path)
        precondition(Set(namesAfterFailure) == [id.uuidString, ".writing-abandoned"])
        do { _ = try inbox.publish(text: nil, files: []); preconditionFailure("Empty share accepted") }
        catch {}
        // A malformed share cannot hide another valid one or escape its package.
        let validSecond = try inbox.publish(text: SharedTextContent(subject: "", text: "second", tags: nil, isHTML: false), files: [])
        let manifest = entry.directory.appendingPathComponent("manifest.json")
        let correctManifest = try Data(contentsOf: manifest)
        var malformed = try JSONSerialization.jsonObject(with: correctManifest) as! [String: Any]
        var attachments = malformed["attachments"] as! [[String: Any]]
        attachments[0]["storedName"] = "../outside.jpg"
        malformed["attachments"] = attachments
        try JSONSerialization.data(withJSONObject: malformed).write(to: manifest)
        let partial = try inbox.scan()
        precondition(partial.entries.map(\.id) == [validSecond] && partial.invalid == [id])
        try correctManifest.write(to: manifest)
        let attachment = entry.transfer.attachments[0]
        let target = entry.file(attachment), replacement = base.appendingPathComponent("replacement")
        try Data("unchanged other data".utf8).write(to: replacement)
        try manager.removeItem(at: target)
        try manager.createSymbolicLink(at: target, withDestinationURL: replacement)
        do { _ = try inbox.read(id); preconditionFailure("Symlink attachment accepted") }
        catch {}
        try inbox.finish(id)
        try inbox.finish(id)
        let untouched = try Data(contentsOf: replacement)
        precondition(untouched == Data("unchanged other data".utf8))
        let afterFinish = try inbox.scan()
        precondition(afterFinish.entries.map(\.id) == [validSecond])
        let consumed = inbox.root.appendingPathComponent(validSecond.uuidString).appendingPathComponent(".consumed")
        try Data().write(to: consumed)
        let afterConsumedMarker = try inbox.scan()
        precondition(afterConsumedMarker.entries.isEmpty)
        print("PASS: immutable share publication, exact copies, original preservation/removal, relaunch persistence, multiple attachments, failed-write cleanup, hidden staging, malformed isolation, traversal/symlink refusal and completed-request suppression")

        // Extension language follows the main app without sharing preferences,
        // profiles or any account data.
        precondition(SharedClientSettings.load(from: base) == nil)
        try SharedClientSettings.save(language: "en", in: base)
        precondition(SharedClientSettings.load(from: base)?.language == "en")
        try SharedClientSettings.save(language: "system", in: base)
        precondition(SharedClientSettings.load(from: base)?.language == "en")
        try Data(#"{"version":2,"language":"ja"}"#.utf8).write(to: base.appendingPathComponent("client-settings.json"))
        precondition(SharedClientSettings.load(from: base) == nil)
        print("PASS: shared language publication and unsupported version/language handling")

        let namespace = UUID().uuidString
        try SharedClientSettings.save(language: "en", in: base, testingNamespace: namespace)
        let productionInbox = base.appendingPathComponent("IncomingShares", isDirectory: true)
        #if DEBUG
        let scoped = productionInbox.appendingPathComponent("UITests", isDirectory: true).appendingPathComponent(namespace, isDirectory: true)
        precondition(SharedClientSettings.extensionInboxDirectory(in: base) == scoped)
        precondition(SharedClientSettings.inboxDirectory(in: base, testingNamespace: namespace) == scoped)
        try SharedClientSettings.save(language: "ja", in: base)
        precondition(SharedClientSettings.extensionInboxDirectory(in: base) == productionInbox)
        #else
        precondition(SharedClientSettings.extensionInboxDirectory(in: base) == productionInbox)
        precondition(SharedClientSettings.inboxDirectory(in: base, testingNamespace: namespace) == productionInbox)
        #endif
        precondition(SharedClientSettings.inboxDirectory(in: base, testingNamespace: "../outside") == productionInbox)
        print("PASS: test inbox scope agrees across app and extension; no overrides in Release; malformed scopes are ignored")

        let configured = "group.com.localtools.studyclient.shared"
        let suffixed = configured + ".ABCDEFGHIJ"
        precondition(SharedGroup.candidates(configured: configured, signed: ["group.other", suffixed, suffixed], legacy: [configured]) == [suffixed, configured])
        precondition(SharedGroup.candidates(configured: configured, signed: [configured + ".", configured + ".bad/name", configured + "-other"]) == [configured])
        precondition(SharedGroup.candidates(configured: "", signed: [suffixed]).isEmpty)
        if CommandLine.arguments.count > 1 {
            let groups = try SignedGroupReader.groups(in: URL(fileURLWithPath: CommandLine.arguments[1]))
            precondition(groups == [suffixed])
        }
        let invalid = base.appendingPathComponent("invalid-executable")
        try Data([0,1,2,3]).write(to: invalid)
        do { _ = try SignedGroupReader.groups(in: invalid); preconditionFailure("Malformed executable accepted") }
        catch {}
        for data in [Data(), Data(repeating: 0xff, count: 40)] {
            do { _ = try SignedGroupReader.groups(inSignature: data); preconditionFailure("Malformed signature accepted") }
            catch {}
        }
        print("PASS: configured versus signed/resigned group selection, foreign/invalid suffix exclusion, actual codesign XML entitlement extraction and malformed signature refusal")
    }
}
