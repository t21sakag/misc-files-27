import Foundation

enum AppText { static func localized(_ value: String) -> String { value } }
struct EngineError: Error { let message: String }
actor Engine {
    var object: Any?
    var writes = 0
    var failWrites = false
    init(_ object: Any? = nil) { self.object = object }
    func configValue(_ key: String) throws -> Any? { precondition(key == "flagLabels"); return object }
    func setConfigValue(_ key: String, value: Any) throws {
        precondition(key == "flagLabels")
        if failWrites { throw EngineError(message: "Injected write failure") }
        object = value; writes += 1
    }
    func fail() { failWrites = true }
}
@main struct FlagLabelsSmoke {
    static func main() async throws {
        let defaults = FlagLabels()
        precondition((0...7).map(defaults.name) == ["なし", "赤", "オレンジ", "緑", "青", "ピンク", "ターコイズ", "紫"])
        precondition(FlagLabels(["1": "", "0": "Not allowed"]).name(1) == "")
        precondition(FlagLabels(["1": "", "0": "Not allowed"]).name(0) == "なし")
        precondition(FlagLabels(["2": 42, "3": true, "4": NSNull()]).name(2) == "42")
        precondition(FlagLabels(["3": true]).name(3) == "true")
        precondition(FlagLabels(["4": NSNull()]).name(4) == "青")
        precondition(FlagLabels(["bad", "shape"]) == defaults)
        let original: [String: Any] = ["1": "Old", "2": 42, "future": ["keep": true], "0": "Ignored"]
        let engine = Engine(original)
        let renamed = try await engine.renameFlag(1, name: "重要 📌")
        precondition(renamed.name(1) == "重要 📌" && renamed.name(2) == "42")
        let stored = await engine.object as! [String: Any]
        precondition(stored["2"] as? Int == 42 && (stored["future"] as? [String: Bool])?["keep"] == true)
        let unchanged = try await engine.renameFlag(1, name: "")
        let writes = await engine.writes
        precondition(unchanged.name(1) == "重要 📌" && writes == 1)
        for code in [0, -1, 8] {
            do { _ = try await engine.renameFlag(code, name: "Bad"); preconditionFailure("Invalid flag was renamed") }
            catch is EngineError {}
        }
        await engine.fail()
        do { _ = try await engine.renameFlag(1, name: "Must fail"); preconditionFailure("Missing write failure") }
        catch is EngineError {}
        let afterFailure = try await engine.flagLabels()
        precondition(afterFailure.name(1) == "重要 📌")
        print("PASS: production flag-name parser/adapter, localized defaults, Android value coercion, no-flag protection, empty no-op, unknown-key preservation and write failure; transport simulated")
    }
}
