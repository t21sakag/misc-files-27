import Foundation

enum AppLanguageChoice: String, CaseIterable, Identifiable {
    case japanese = "ja", english = "en", system
    static let preferenceKey = "appLanguage"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .japanese: "日本語"
        case .english: "English"
        case .system: AppText.localized("システム")
        }
    }
    static func load(_ defaults: UserDefaults = .standard) -> Self {
        // Existing installations retain Japanese until the user chooses otherwise.
        Self(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? .japanese
    }
    func save(_ defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.preferenceKey) }
    func resolved(preferences: [String] = Locale.preferredLanguages) -> String {
        switch self {
        case .japanese: "ja"
        case .english: "en"
        case .system: Bundle.preferredLocalizations(from: ["en", "ja"], forPreferences: preferences).first ?? "en"
        }
    }
}

enum AppText {
    // Read once per process. Saving a choice never closes an engine, interrupts
    // sync, or changes the language underneath an unsaved editor.
    static let language = AppLanguageChoice.load().resolved()
    static let bundle: Bundle = {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let localized = Bundle(path: path) else { return .main }
        return localized
    }()
    static var backendLanguages: [String] { language == "ja" ? ["ja", "en"] : ["en"] }
    static var locale: Locale {
        // Preserve the user's region while selecting the interface language.
        Locale(identifier: language + (Locale.current.region.map { "_" + $0.identifier } ?? ""))
    }
    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = locale
        return calendar
    }
    static func localized(_ value: String.LocalizationValue, bundle: Bundle = AppText.bundle) -> String {
        String(localized: value, bundle: bundle, locale: .current)
    }
}
