#if DEBUG
import Foundation

/// Test launches get a private Application Support root and Keychain namespace.
/// Repeated launches within the same case retain profiles, tokens and settings.
/// Release builds contain no override or reset path.
enum UITestIsolation {
    static func namespace(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        guard let raw = environment["ANKIPAD_UI_TEST_NAMESPACE"], let uuid = UUID(uuidString: raw) else { return nil }
        return uuid.uuidString
    }
    static func support(base: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
                        environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        guard let namespace = namespace(environment: environment) else { return nil }
        return base.appendingPathComponent("UITests", isDirectory: true).appendingPathComponent(namespace, isDirectory: true)
    }
    static func prepare(defaults: UserDefaults = .standard, domain: String? = Bundle.main.bundleIdentifier,
                        base: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
                        environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        guard let root = support(base: base, environment: environment) else { return }
        let marker = root.appendingPathComponent("initialized")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        guard let domain else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaults.removePersistentDomain(forName: domain)
        try Data().write(to: marker, options: .atomic)
    }
}
#endif
