import Foundation

@main struct UITestIsolationSmoke {
    static func main() throws {
        let name = "isolation-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let first = ["ANKIPAD_UI_TEST_NAMESPACE": UUID().uuidString]
        let second = ["ANKIPAD_UI_TEST_NAMESPACE": UUID().uuidString]
        defaults.set("old-case", forKey: "setting")
        try UITestIsolation.prepare(defaults: defaults, domain: name, base: base, environment: first)
        precondition(defaults.string(forKey: "setting") == nil)
        defaults.set("retained-on-relaunch", forKey: "setting")
        try UITestIsolation.prepare(defaults: defaults, domain: name, base: base, environment: first)
        precondition(defaults.string(forKey: "setting") == "retained-on-relaunch")
        precondition(UITestIsolation.support(base: base, environment: first) != UITestIsolation.support(base: base, environment: second))
        try UITestIsolation.prepare(defaults: defaults, domain: name, base: base, environment: second)
        precondition(defaults.string(forKey: "setting") == nil)
        defaults.set("normal-debug-app", forKey: "setting")
        let invalid = ["ANKIPAD_UI_TEST_NAMESPACE": "../../other"]
        try UITestIsolation.prepare(defaults: defaults, domain: name, base: base, environment: invalid)
        precondition(UITestIsolation.support(base: base, environment: invalid) == nil)
        precondition(UITestIsolation.support(base: base, environment: [:]) == nil)
        precondition(defaults.string(forKey: "setting") == "normal-debug-app")
        print("PASS: distinct case roots; settings reset once; relaunch retains state; normal/invalid launches stay untouched")
    }
}
