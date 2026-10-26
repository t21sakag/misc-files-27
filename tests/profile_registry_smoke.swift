import Foundation

@main struct ProfileRegistrySmoke {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ankipad-profiles-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProfileRegistryStore(support: folder)
        var registry = try store.load()
        let legacy = try store.root(for: "default")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let original = legacy.appendingPathComponent("collection.anki2")
        try Data("legacy-preserved".utf8).write(to: original)
        registry = try store.adding("Second", to: registry)
        let secondID = registry.profiles.last!.id
        let second = try store.root(for: secondID)
        precondition(!second.path.hasPrefix(legacy.path + "/"))
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try Data("second-preserved".utf8).write(to: second.appendingPathComponent("collection.anki2"))
        registry = try store.renaming(secondID, to: "Renamed", in: registry)
        let renamedRoot = try store.root(for: secondID)
        precondition(renamedRoot == second)
        let legacyBytes = try Data(contentsOf: original)
        precondition(legacyBytes == Data("legacy-preserved".utf8))
        registry = try store.selecting(secondID, in: registry)
        let reloaded = try store.load()
        precondition(reloaded.selectedID == secondID)
        do { _ = try store.deletingInactive(secondID, in: registry); preconditionFailure("Deleted active profile") } catch is ProfileRegistryError {}
        registry = try store.deletingInactive("default", in: registry)
        precondition(!FileManager.default.fileExists(atPath: legacy.path))
        let preserved = try Data(contentsOf: second.appendingPathComponent("collection.anki2"))
        precondition(preserved == Data("second-preserved".utf8))
        do { _ = try store.root(for: "../../private"); preconditionFailure("Accepted path traversal") } catch is ProfileRegistryError {}
        do { _ = try store.adding("renamed", to: registry); preconditionFailure("Accepted duplicate name") } catch is ProfileRegistryError {}
        registry = try store.adding("Rollback", to: registry)
        let rollbackID = registry.profiles.last!.id
        let rollback = try store.root(for: rollbackID)
        try FileManager.default.createDirectory(at: rollback, withIntermediateDirectories: true)
        let sentinel = rollback.appendingPathComponent("sentinel")
        try Data("rollback-preserved".utf8).write(to: sentinel)
        let manifest = try Data(contentsOf: store.file)
        try FileManager.default.removeItem(at: store.file)
        try FileManager.default.createDirectory(at: store.file, withIntermediateDirectories: true)
        do { _ = try store.deletingInactive(rollbackID, in: registry); preconditionFailure("Unexpected save success") } catch {}
        let restored = try Data(contentsOf: sentinel)
        precondition(restored == Data("rollback-preserved".utf8))
        try FileManager.default.removeItem(at: store.file)
        try manifest.write(to: store.file)
        let before = try Data(contentsOf: second.appendingPathComponent("collection.anki2"))
        try Data("broken-json".utf8).write(to: store.file)
        do { _ = try store.load(); preconditionFailure("Silently replaced corrupt registry") } catch is ProfileRegistryError {}
        let after = try Data(contentsOf: second.appendingPathComponent("collection.anki2"))
        precondition(after == before)
        try FileManager.default.removeItem(at: store.file)
        do { _ = try store.load(); preconditionFailure("Replaced missing profile registry") } catch is ProfileRegistryError {}
        print("PASS: actual profile registry + legacy root preservation + persistence + rename + safe deletion + active guard + traversal/duplicate/corruption rejection")
    }
}
