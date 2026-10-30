import Foundation

enum AppText { static func localized(_ value: String) -> String { value } }
struct EngineError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
actor Engine {
    var values: [String: Any] = ["BROWSER_TABLE_SHOW_NOTES_MODE": false, "IGNORE_ACCENTS_IN_SEARCH": false, "DEFAULT_SEARCH_TEXT": ""]
    var writeCount = 0
    let failWrites: Set<Int>
    init(failWrites: Set<Int> = []) { self.failWrites = failWrites }
    func call(_ method: String, _ args: [String: Any] = [:]) throws -> [String: Any] {
        guard let key = args["key"] as? String, values[key] != nil else { preconditionFailure("Unknown preference") }
        switch method {
        case "ConfigService.GetConfigBool", "ConfigService.GetConfigString": return ["val": values[key]!]
        case "ConfigService.SetConfigBool", "ConfigService.SetConfigString":
            writeCount += 1
            if failWrites.contains(writeCount) { throw EngineError(message: "Injected persistence failure") }
            values[key] = args["value"]!
            return [:]
        default: preconditionFailure("Unexpected engine operation: " + method)
        }
    }
}
@main struct BrowserOptionsSmoke {
    static func main() async throws {
        let desired = BrowserOptions(notesMode: true, ignoreAccents: true, defaultSearch: "deck:\"日本語\" or tag:café")
        let engine = Engine()
        let defaults = try await engine.browserOptions()
        precondition(defaults == BrowserOptions())
        try await engine.saveBrowserOptions(desired)
        let saved = try await engine.browserOptions()
        precondition(saved == desired)
        let writes = await engine.writeCount
        try await engine.saveBrowserOptions(desired)
        let noOpWrites = await engine.writeCount
        precondition(writes == 3 && noOpWrites == writes, "Unchanged options must not write")
        for failure in 1...3 {
            let failing = Engine(failWrites: [failure])
            do { try await failing.saveBrowserOptions(desired); preconditionFailure("Expected injected failure") }
            catch { precondition(error.localizedDescription == "Injected persistence failure") }
            let restored = try await failing.browserOptions()
            precondition(restored == defaults, "Partial preference writes were not restored")
        }
        let doubleFailure = Engine(failWrites: [2, 3])
        do { try await doubleFailure.saveBrowserOptions(desired); preconditionFailure("Expected rollback failure") }
        catch { precondition(error.localizedDescription == "設定の保存に失敗し、元の設定に戻せませんでした。") }
        print("PASS: production browser options adapter, round trip/no-op, all write failure boundaries and reported rollback failure; transport simulated")
    }
}
