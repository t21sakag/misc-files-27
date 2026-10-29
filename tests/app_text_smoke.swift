import Foundation

@main struct AppTextSmoke {
    static func main() throws {
        let resources = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let japanese = Bundle(path: resources.appendingPathComponent("ja.lproj").path)!
        let english = Bundle(path: resources.appendingPathComponent("en.lproj").path)!
        for (language, bundle) in [("ja", japanese), ("en", english)] {
            let bytes = try Data(contentsOf: resources.appendingPathComponent(language + ".lproj/Localizable.strings"))
            let table = try PropertyListSerialization.propertyList(from: bytes, format: nil) as! [String: String]
            for (key, expected) in table {
                precondition(bundle.localizedString(forKey: key, value: nil, table: nil) == expected, key)
            }
        }
        precondition(AppText.localized("保存", bundle: japanese) == "保存")
        precondition(AppText.localized("保存", bundle: english) == "Save")
        precondition(AppText.localized("アップロード", bundle: english) == "Upload")
        let count = 3, selected = 1
        precondition(AppText.localized("\(count)枚 · \(selected)件選択中", bundle: english) == "Cards: 3 · Selected: 1")
        precondition(AppText.localized("このiPad: デッキ \(1)個・カード \(count)枚", bundle: english) == "This iPad · Decks: 1 · Cards: 3")
        let zoom = "150%", name = "保存 %@ \\\" <img>"
        precondition(AppText.localized("画像の拡大率: \(zoom)", bundle: english) == "Image zoom: 150%")
        precondition(AppText.localized("\(name)を展開", bundle: english) == "Expand " + name)
        precondition(AppText.localized("\(name)を展開", bundle: japanese) == name + "を展開")
        precondition(AppText.localized("\(1)分で\(selected)枚に回答しました。", bundle: japanese) == "1分で1枚に回答しました。")
        precondition(AppText.localized("存在しない翻訳", bundle: english) == "存在しない翻訳")

        let suite = "AppTextSmoke." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(AppLanguageChoice.load(defaults) == .japanese)
        defaults.set("unsupported", forKey: AppLanguageChoice.preferenceKey)
        precondition(AppLanguageChoice.load(defaults) == .japanese)
        AppLanguageChoice.english.save(defaults)
        precondition(AppLanguageChoice.load(defaults) == .english)
        precondition(AppLanguageChoice.english.resolved(preferences: ["ja-JP"]) == "en")
        precondition(AppLanguageChoice.japanese.resolved(preferences: ["en-US"]) == "ja")
        precondition(AppLanguageChoice.system.resolved(preferences: ["fr-FR", "ja-JP"]) == "ja")
        precondition(AppLanguageChoice.system.resolved(preferences: ["en-GB"]) == "en")
        precondition(AppLanguageChoice.system.resolved(preferences: ["zz-ZZ"]) == "en")
        print("PASS: actual ja/en bundle lookup, typed count/string/percent interpolation, literal user data, upload token, missing-key fallback and stored/system language policy")
    }
}
