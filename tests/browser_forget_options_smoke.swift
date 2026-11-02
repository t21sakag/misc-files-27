import Foundation

@main struct BrowserForgetOptionsSmoke {
    static func main() throws {
        let name = "ForgetOptions-" + UUID().uuidString, key = "profile.first.browserForgetOptions"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let original = try BrowserForgetOptions.load(key: key, defaults: defaults)
        precondition(original == BrowserForgetOptions())
        var draft = original; draft.restorePosition = false; draft.resetCounts = true
        let unchanged = try BrowserForgetOptions.load(key: key, defaults: defaults)
        precondition(unchanged == original, "Editing an unconfirmed draft must not persist")
        let args = try draft.arguments(cardIDs: ["23", "17"])
        precondition(args["cardIds"] as? [String] == ["23", "17"] && args["log"] as? Bool == true)
        precondition(args["restorePosition"] as? Bool == false && args["resetCounts"] as? Bool == true && args["context"] == nil)
        for ids in [[], ["0"], ["-1"], ["01"], ["+1"], [" 1"], ["9223372036854775808"], ["1", "1"]] {
            do { _ = try draft.arguments(cardIDs: ids); preconditionFailure("Invalid scheduling targets accepted") } catch {}
        }
        try draft.save(key: key, defaults: defaults)
        let reopened = try BrowserForgetOptions.load(key: key, defaults: UserDefaults(suiteName: name)!)
        precondition(reopened == draft)
        let isolated = try BrowserForgetOptions.load(key: "profile.second.browserForgetOptions", defaults: defaults)
        precondition(isolated == original)
        for value: Any in ["bad", Data("broken".utf8), Data("{\"version\":2,\"options\":{\"restorePosition\":true,\"resetCounts\":false}}".utf8)] {
            defaults.set(value, forKey: key)
            let before = defaults.object(forKey: key) as! NSObject
            do { try draft.save(key: key, defaults: defaults); preconditionFailure("Unknown options were overwritten") }
            catch { precondition(before.isEqual(defaults.object(forKey: key))) }
        }
        print("PASS: reset draft/cancel, confirmed profile-isolated options, preserved target order, invalid target rejection and corrupt/future preferences retained")
    }
}
