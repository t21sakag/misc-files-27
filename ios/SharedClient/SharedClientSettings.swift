import Foundation

struct SharedClientSettings: Codable, Sendable {
    let version: Int
    let language: String
    #if DEBUG
    var testingNamespace: String?
    #endif
    static func inboxDirectory(in container: URL, testingNamespace: String? = nil) -> URL {
        let root = container.appendingPathComponent("IncomingShares", isDirectory: true)
        #if DEBUG
        if let testingNamespace, let id = UUID(uuidString: testingNamespace) {
            return root.appendingPathComponent("UITests", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
        }
        #endif
        return root
    }
    static func extensionInboxDirectory(in container: URL) -> URL {
        #if DEBUG
        return inboxDirectory(in: container, testingNamespace: load(from: container)?.testingNamespace)
        #else
        return inboxDirectory(in: container)
        #endif
    }
    static func load(from container: URL) -> SharedClientSettings? {
        let file = container.appendingPathComponent("client-settings.json")
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16384,
              let data = try? Data(contentsOf: file), let settings = try? JSONDecoder().decode(Self.self, from: data),
              settings.version == 1, ["ja", "en"].contains(settings.language) else { return nil }
        return settings
    }
    static func save(language: String, in container: URL, testingNamespace: String? = nil) throws {
        guard ["ja", "en"].contains(language) else { return }
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        var settings = Self(version: 1, language: language)
        #if DEBUG
        settings.testingNamespace = testingNamespace.flatMap { UUID(uuidString: $0)?.uuidString }
        #endif
        try JSONEncoder().encode(settings)
            .write(to: container.appendingPathComponent("client-settings.json"), options: .atomic)
    }
}
