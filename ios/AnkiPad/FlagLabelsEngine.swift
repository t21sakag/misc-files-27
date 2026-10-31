import Foundation

extension Engine {
    func flagLabels() throws -> FlagLabels { FlagLabels(try configValue("flagLabels")) }
    func renameFlag(_ code: Int, name: String) throws -> FlagLabels {
        guard (1...7).contains(code) else { throw EngineError(message: AppText.localized("フラグを選択してください。")) }
        let original = try configValue("flagLabels")
        // AnkiDroid retains the old title when an empty name is saved.
        guard !name.isEmpty else { return FlagLabels(original) }
        var values = original as? [String: Any] ?? [:]
        values[String(code)] = name
        // Preserve unknown keys and every other flag's stored representation.
        try setConfigValue("flagLabels", value: values)
        return FlagLabels(values)
    }
}
