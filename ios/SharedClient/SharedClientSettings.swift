import Foundation

struct SharedClientSettings: Codable, Sendable {
    let version: Int
    let language: String
    static func load(from container: URL) -> SharedClientSettings? {
        let file = container.appendingPathComponent("client-settings.json")
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16384,
              let data = try? Data(contentsOf: file), let settings = try? JSONDecoder().decode(Self.self, from: data),
              settings.version == 1, ["ja", "en"].contains(settings.language) else { return nil }
        return settings
    }
    static func save(language: String, in container: URL) throws {
        guard ["ja", "en"].contains(language) else { return }
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try JSONEncoder().encode(Self(version: 1, language: language))
            .write(to: container.appendingPathComponent("client-settings.json"), options: .atomic)
    }
}
