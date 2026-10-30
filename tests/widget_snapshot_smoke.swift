import Foundation

@main struct WidgetSnapshotSmoke {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let profileID = UUID().uuidString
        let deck = WidgetDeckSnapshot(id: "9223372036854775807", name: "Parent::Child", counts: WidgetCounts(new: 2, learning: 3, review: 4))
        let collection = WidgetCollectionSnapshot(updatedAt: now, nextDayAt: now.addingTimeInterval(3600), counts: deck.counts,
            etaMinutes: 4, selectedDeckID: deck.id, decks: [deck])
        let original = WidgetSnapshot(selectedProfileID: "default", profiles: [
            WidgetProfileSnapshot(id: "default", name: "Primary", collection: collection),
            WidgetProfileSnapshot(id: profileID, name: "Secondary", collection: nil)])
        let missing = try store.load()
        precondition(missing == nil)
        try store.save(original)
        let loaded = try store.load()
        precondition(loaded == original)
        precondition(collection.isCurrent(at: now))
        precondition(!collection.isCurrent(at: collection.nextDayAt))
        precondition(!collection.isCurrent(at: now.addingTimeInterval(-301)))
        let renamed = WidgetSnapshot.updating(original, profiles: [
            WidgetProfileSnapshot(id: "default", name: "Renamed", collection: nil),
            WidgetProfileSnapshot(id: profileID, name: "Secondary", collection: nil)], selectedID: profileID, collection: nil)
        precondition(renamed.profiles[0].name == "Renamed" && renamed.profiles[0].collection == collection)
        precondition(renamed.profiles[1].collection == nil)
        let removed = WidgetSnapshot.updating(renamed, profiles: [WidgetProfileSnapshot(id: profileID, name: "Secondary", collection: nil)],
            selectedID: profileID, collection: collection)
        try store.save(removed)
        let afterRemoval = try store.load()
        precondition(afterRemoval == removed && removed.profiles.count == 1)
        var invalid = removed; invalid.version = 2
        do { try store.save(invalid); fatalError("Accepted unsupported version") } catch WidgetSnapshotStore.StorageError.invalidSnapshot {}
        let afterFailure = try store.load()
        precondition(afterFailure == removed, "Failed write replaced a valid snapshot")
        try Data("{\"version\":2}".utf8).write(to: store.file, options: .atomic)
        do { _ = try store.load(); fatalError("Accepted truncated/unsupported data") } catch {}
        let namespace = UUID().uuidString
        let path = WidgetSnapshotStore.directory(in: directory, testingNamespace: namespace).path
        #if DEBUG
        precondition(path.contains(namespace))
        #else
        precondition(!path.contains(namespace))
        #endif
        for action in [WidgetRoute.Destination.home, .review, .options, .add] {
            let route = WidgetRoute(profileID: profileID, deckID: deck.id, destination: action)
            precondition(WidgetRoute(url: route.url) == route)
        }
        let orderedSnapshot = WidgetSnapshot(selectedProfileID: "default", profiles: [
            WidgetProfileSnapshot(id: "default", name: "First", collection: collection),
            WidgetProfileSnapshot(id: profileID, name: "Second", collection: collection)])
        let firstReference = WidgetDeckReference(profileID: "default", deckID: deck.id).identifier
        let secondReference = WidgetDeckReference(profileID: profileID, deckID: deck.id).identifier
        let rows = orderedSnapshot.deckRows(for: ["default:999", secondReference, "invalid", firstReference])
        precondition(rows.map { $0.profile.id } == [profileID, "default"], "Deleted decks must not consume rows or reorder surviving choices")
        precondition(rows.prefix(1).first?.profile.id == profileID, "Filter before applying family row capacity")
        precondition(rows.first?.deck.displayName == "Child", "Native widget uses the last deck-name component")
        precondition(removed.deckRows(for: [firstReference]).isEmpty, "Deleted profile must never resolve in another collection")
        precondition(orderedSnapshot.deckRows(for: ["default:999"]).isEmpty)
        let reference = WidgetDeckReference(profileID: profileID, deckID: deck.id)
        precondition(WidgetDeckReference(identifier: reference.identifier) == reference)
        precondition(reference.identifier != WidgetDeckReference(profileID: "default", deckID: deck.id).identifier)
        for invalid in ["default:0", "other:1", "default:1:2", "default:", "default:01"] {
            precondition(WidgetDeckReference(identifier: invalid) == nil)
        }
        let invalidURLs = ["studyclient://widget/review?profile=default", "studyclient://widget/add?profile=../elsewhere",
            "studyclient://widget/options?profile=default&deck=-1", "studyclient://widget/add?profile=default&profile=" + profileID,
            "studyclient://widget/home?profile=default&deck=01", "studyclient://widget/home?profile=default&callback=https://example.invalid",
            "https://widget/home?profile=default", "studyclient://widget/home/extra?profile=default", "studyclient://widget:80/home?profile=default"]
        for url in invalidURLs { precondition(WidgetRoute(url: URL(string: url)!) == nil, url) }
        print("PASS: widget atomic snapshots, profile pruning/renaming, expiry, failure preservation, Debug/Release scope, strict route roundtrips")
    }
}
