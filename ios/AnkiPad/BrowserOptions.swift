import Foundation

struct BrowserOptions: Equatable {
    var notesMode = false
    var ignoreAccents = false
    var defaultSearch = ""
}

extension Engine {
    func browserOptions() throws -> BrowserOptions {
        BrowserOptions(notesMode: try call("ConfigService.GetConfigBool", ["key": "BROWSER_TABLE_SHOW_NOTES_MODE"])["val"] as? Bool ?? false,
            ignoreAccents: try call("ConfigService.GetConfigBool", ["key": "IGNORE_ACCENTS_IN_SEARCH"])["val"] as? Bool ?? false,
            defaultSearch: try call("ConfigService.GetConfigString", ["key": "DEFAULT_SEARCH_TEXT"])["val"] as? String ?? "")
    }
    func saveBrowserOptions(_ options: BrowserOptions) throws {
        let previous = try browserOptions()
        // All calls run in this engine actor turn. Compensate completed writes
        // if a later preference cannot be persisted; never silently report a
        // partial save as success.
        let writes: [(String, [String: Any], [String: Any], Bool)] = [
            ("ConfigService.SetConfigBool", ["key": "BROWSER_TABLE_SHOW_NOTES_MODE", "value": options.notesMode], ["key": "BROWSER_TABLE_SHOW_NOTES_MODE", "value": previous.notesMode], options.notesMode != previous.notesMode),
            ("ConfigService.SetConfigBool", ["key": "IGNORE_ACCENTS_IN_SEARCH", "value": options.ignoreAccents], ["key": "IGNORE_ACCENTS_IN_SEARCH", "value": previous.ignoreAccents], options.ignoreAccents != previous.ignoreAccents),
            ("ConfigService.SetConfigString", ["key": "DEFAULT_SEARCH_TEXT", "value": options.defaultSearch], ["key": "DEFAULT_SEARCH_TEXT", "value": previous.defaultSearch], options.defaultSearch != previous.defaultSearch)
        ]
        var completed: [(String, [String: Any])] = []
        do {
            for (method, value, oldValue, changed) in writes where changed {
                _ = try call(method, value)
                completed.append((method, oldValue))
            }
        } catch {
            var rollbackFailed = false
            for (method, value) in completed.reversed() {
                do { _ = try call(method, value) } catch { rollbackFailed = true }
            }
            if rollbackFailed { throw EngineError(message: AppText.localized("設定の保存に失敗し、元の設定に戻せませんでした。")) }
            throw error
        }
    }
}
