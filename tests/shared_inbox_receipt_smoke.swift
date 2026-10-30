import Foundation

@main struct SharedReceiptSmoke {
    @MainActor static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("ReceiptSmoke-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        let inbox = SharedInbox(root: root.appendingPathComponent("inbox"))
        let content = SharedTextContent(subject: "", text: "Keep until committed", tags: nil, isHTML: false)
        let id = try inbox.publish(text: content, files: [])
        var outcomes: [Bool] = []
        let cancelled = SharedInboxReceipt(id: id, inbox: inbox) { _, success in outcomes.append(success) }
        cancelled.deferUntilRequested(); cancelled.deferUntilRequested()
        let late = await cancelled.accept()
        precondition(!late && outcomes == [false])
        let pending = try inbox.scan()
        precondition(pending.entries.map(\.id) == [id])
        let committed = SharedInboxReceipt(id: id, inbox: inbox) { _, success in outcomes.append(success) }
        async let first = committed.accept()
        async let second = committed.accept()
        let results = await (first, second)
        committed.deferUntilRequested()
        precondition(results.0 && results.1 && outcomes == [false, true])
        let finished = try inbox.scan()
        precondition(finished.entries.isEmpty)
        // A failed acknowledgement must leave the source intact and resolve
        // once as retained, so an import failure can be reopened manually.
        let failedID = try inbox.publish(text: content, files: [])
        let directory = inbox.root.appendingPathComponent(failedID.uuidString)
        let original = root.appendingPathComponent("original")
        try manager.moveItem(at: directory, to: original)
        try manager.createSymbolicLink(at: directory, withDestinationURL: original)
        let failure = SharedInboxReceipt(id: failedID, inbox: inbox) { _, success in outcomes.append(success) }
        let accepted = await failure.accept()
        failure.deferUntilRequested()
        precondition(!accepted && outcomes == [false,true,false])
        precondition(manager.fileExists(atPath: original.appendingPathComponent("manifest.json").path))
        print("PASS: cancellation retains the request; concurrent committed acknowledgements publish one result; storage failure preserves content and releases it once")
    }
}
