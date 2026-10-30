import Foundation

/// Display data only. The widget never receives a collection path, card text,
/// account, or permission to open the app's database.
struct WidgetCounts: Codable, Equatable {
    let new: Int
    let learning: Int
    let review: Int
    var total: Int { new + learning + review }
    var isValid: Bool { [new, learning, review].allSatisfy { (0...Int(Int32.max)).contains($0) } }
}

struct WidgetDeckSnapshot: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let counts: WidgetCounts
    var displayName: String {
        let leaf = name.components(separatedBy: "::").last ?? name
        return leaf.isEmpty ? name : leaf
    }
}

struct WidgetCollectionSnapshot: Codable, Equatable {
    let updatedAt: Date
    let nextDayAt: Date
    let counts: WidgetCounts
    let etaMinutes: Int?
    let selectedDeckID: String?
    let decks: [WidgetDeckSnapshot]

    func isCurrent(at date: Date) -> Bool { date >= updatedAt.addingTimeInterval(-300) && date < nextDayAt }
    var isValid: Bool {
        updatedAt.timeIntervalSince1970.isFinite && nextDayAt.timeIntervalSince1970.isFinite
        && nextDayAt > updatedAt && nextDayAt.timeIntervalSince(updatedAt) <= 2 * 86400
        && counts.isValid && (etaMinutes == nil || (0...Int(Int32.max)).contains(etaMinutes!))
        && Set(decks.map(\.id)).count == decks.count
        && decks.allSatisfy { WidgetRoute.validDeckID($0.id) && !$0.name.isEmpty && $0.counts.isValid }
        && (selectedDeckID == nil || decks.contains { $0.id == selectedDeckID })
    }
}

struct WidgetProfileSnapshot: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    var collection: WidgetCollectionSnapshot?
}

struct WidgetSnapshot: Codable, Equatable {
    var version = 1
    var selectedProfileID: String
    var profiles: [WidgetProfileSnapshot]

    /// Preserve configured order while omitting deleted decks, as the original
    /// deck-picker widget does. Resolve profile and deck together: equal deck
    /// numbers in different collections must never become interchangeable.
    func deckRows(for identifiers: [String]) -> [(profile: WidgetProfileSnapshot, collection: WidgetCollectionSnapshot, deck: WidgetDeckSnapshot)] {
        identifiers.compactMap { identifier in
            guard let reference = WidgetDeckReference(identifier: identifier),
                  let profile = profiles.first(where: { $0.id == reference.profileID }),
                  let collection = profile.collection,
                  let deck = collection.decks.first(where: { $0.id == reference.deckID }) else { return nil }
            return (profile, collection, deck)
        }
    }

    var isValid: Bool {
        version == 1 && !profiles.isEmpty && Set(profiles.map(\.id)).count == profiles.count
        && profiles.contains { $0.id == selectedProfileID }
        && profiles.allSatisfy { WidgetRoute.validProfileID($0.id) && !$0.name.isEmpty && $0.name.count <= 80 && ($0.collection?.isValid ?? true) }
    }

    /// The registry, rather than an old snapshot, owns names and existence.
    /// Pruning here removes deleted profiles even if none of their decks changed.
    static func updating(_ previous: Self?, profiles: [WidgetProfileSnapshot], selectedID: String,
                         collection: WidgetCollectionSnapshot?) -> Self {
        Self(selectedProfileID: selectedID, profiles: profiles.map { profile in
            WidgetProfileSnapshot(id: profile.id, name: profile.name, collection: profile.id == selectedID
                ? collection : previous?.profiles.first { $0.id == profile.id }?.collection)
        })
    }
}

struct WidgetSnapshotStore {
    enum StorageError: Error { case invalidSnapshot, oversizedSnapshot }
    static let byteLimit = 8 * 1024 * 1024
    let directory: URL
    var file: URL { directory.appendingPathComponent("snapshot.json") }

    static func directory(in container: URL, testingNamespace: String? = nil) -> URL {
        let root = container.appendingPathComponent("WidgetDisplay", isDirectory: true)
        #if DEBUG
        if let testingNamespace, let id = UUID(uuidString: testingNamespace) {
            return root.appendingPathComponent("UITests", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
        }
        #endif
        return root
    }
    func load() throws -> WidgetSnapshot? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= Self.byteLimit else { throw StorageError.oversizedSnapshot }
        let value = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(contentsOf: file))
        guard value.isValid else { throw StorageError.invalidSnapshot }
        return value
    }
    func save(_ value: WidgetSnapshot) throws {
        guard value.isValid else { throw StorageError.invalidSnapshot }
        let data = try JSONEncoder().encode(value)
        guard data.count <= Self.byteLimit else { throw StorageError.oversizedSnapshot }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var resource = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try resource.setResourceValues(values)
        try data.write(to: file, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
        #endif
    }
}
