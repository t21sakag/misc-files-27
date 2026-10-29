import Foundation

enum StudyDayTheme: String, CaseIterable, Identifiable {
    case light = "1", plain = "2", eink = "3"
    var id: String { rawValue }
    var title: String { switch self { case .light: AppText.localized("ライト"); case .plain: AppText.localized("プレーン"); case .eink: "E Ink" } }
}
enum StudyNightTheme: String, CaseIterable, Identifiable {
    case black = "3", dark = "4"
    var id: String { rawValue }
    var title: String { switch self { case .black: AppText.localized("ブラック"); case .dark: AppText.localized("ダーク") } }
}
enum StudyTheme: String {
    case light, plain, eink, black, dark
    static func resolve(dark: Bool, day: String, night: String) -> Self {
        if dark { return StudyNightTheme(rawValue: night) == .dark ? .dark : .black }
        switch StudyDayTheme(rawValue: day) ?? .light {
        case .light: return .light
        case .plain: return .plain
        case .eink: return .eink
        }
    }
    var isMonochrome: Bool { self == .plain || self == .eink }
    var cardClasses: String {
        switch self {
        case .black: "night_mode nightMode"
        case .dark: "night_mode nightMode ankidroid_dark_mode"
        case .plain: "ankidroid_plain_mode"
        case .light, .eink: ""
        }
    }
    // Precede template CSS so a card's own night-mode rules still take effect.
    static let cardCSS = """
    body{background-color:white;color:black}
    body.night_mode{background-color:black;color:white}
    body.ankidroid_dark_mode{background-color:#303030}
    """
}
