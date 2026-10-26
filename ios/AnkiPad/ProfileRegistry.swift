import Foundation

struct StudyProfile: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    static let legacy = StudyProfile(id: "default", name: "既定")
}
struct ProfileRegistry: Codable {
    var profiles: [StudyProfile]
    var selectedID: String
    static let initial = ProfileRegistry(profiles: [.legacy], selectedID: "default")
}
struct ProfileRegistryError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
/// Only this registry owns profile directories; names are never used as paths.
final class ProfileRegistryStore {
    let support: URL
    var file: URL { support.appendingPathComponent("AnkiPad-profiles.json") }
    init(support: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]) { self.support = support }
    func root(for id: String) throws -> URL {
        if id == "default" { return support.appendingPathComponent("AnkiPad", isDirectory: true) }
        guard let uuid = UUID(uuidString: id), uuid.uuidString == id else { throw failure("プロファイルの識別子が正しくありません。") }
        return support.appendingPathComponent("AnkiPad-Profiles", isDirectory: true).appendingPathComponent(uuid.uuidString, isDirectory: true)
    }
    func load() throws -> ProfileRegistry {
        guard FileManager.default.fileExists(atPath: file.path) else {
            let named = support.appendingPathComponent("AnkiPad-Profiles", isDirectory: true)
            let existing = (try? FileManager.default.contentsOfDirectory(atPath: named.path)) ?? []
            guard existing.isEmpty else { throw failure("保存済みのプロファイル一覧が見つかりません。デッキのファイルは変更していません。") }
            try save(.initial); return .initial
        }
        do {
            let value = try JSONDecoder().decode(ProfileRegistry.self, from: Data(contentsOf: file))
            try validate(value)
            return value
        } catch {
            throw failure("プロファイル一覧を読み込めませんでした。保存済みのデッキは変更していません。")
        }
    }
    func save(_ registry: ProfileRegistry) throws {
        try validate(registry)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try JSONEncoder().encode(registry).write(to: file, options: .atomic)
    }
    func adding(_ name: String, to registry: ProfileRegistry) throws -> ProfileRegistry {
        var result = registry
        let name = try checkedName(name, except: nil, in: registry)
        result.profiles.append(StudyProfile(id: UUID().uuidString, name: name))
        try save(result)
        return result
    }
    func renaming(_ id: String, to name: String, in registry: ProfileRegistry) throws -> ProfileRegistry {
        guard let index = registry.profiles.firstIndex(where: { $0.id == id }) else { throw failure("プロファイルが見つかりません。") }
        var result = registry
        result.profiles[index].name = try checkedName(name, except: id, in: registry)
        try save(result)
        return result
    }
    func selecting(_ id: String, in registry: ProfileRegistry) throws -> ProfileRegistry {
        var result = registry
        result.selectedID = id
        try save(result)
        return result
    }
    func deletingInactive(_ id: String, in registry: ProfileRegistry) throws -> ProfileRegistry {
        guard id != registry.selectedID else { throw failure("使用中のプロファイルは削除できません。別のプロファイルに切り替えてください。") }
        guard registry.profiles.count > 1, registry.profiles.contains(where: { $0.id == id }) else { throw failure("削除するプロファイルが見つかりません。") }
        let original = try root(for: id)
        let trash = support.appendingPathComponent("AnkiPad-ProfileTrash", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exists = FileManager.default.fileExists(atPath: original.path)
        if exists {
            try FileManager.default.createDirectory(at: trash.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: original, to: trash)
        }
        var result = registry
        result.profiles.removeAll { $0.id == id }
        do { try save(result) }
        catch {
            if exists { try FileManager.default.moveItem(at: trash, to: original) }
            throw error
        }
        if exists { try? FileManager.default.removeItem(at: trash) }
        return result
    }
    private func validate(_ registry: ProfileRegistry) throws {
        guard !registry.profiles.isEmpty, Set(registry.profiles.map(\.id)).count == registry.profiles.count,
              registry.profiles.contains(where: { $0.id == registry.selectedID }) else { throw failure("プロファイル一覧が正しくありません。") }
        var names = Set<String>()
        for profile in registry.profiles {
            _ = try root(for: profile.id)
            let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 80, names.insert(name.lowercased()).inserted else { throw failure("プロファイル名が正しくありません。") }
        }
    }
    private func checkedName(_ raw: String, except id: String?, in registry: ProfileRegistry) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { throw failure("プロファイル名を1〜80文字で入力してください。") }
        guard !registry.profiles.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { throw failure("同じ名前のプロファイルがあります。") }
        return name
    }
    private func failure(_ message: String) -> ProfileRegistryError { ProfileRegistryError(message: message) }
}
