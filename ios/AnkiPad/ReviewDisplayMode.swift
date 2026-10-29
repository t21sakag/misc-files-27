import Foundation

enum ReviewDisplayMode: Int, CaseIterable, Identifiable {
    case buttonsAndMenu = 0
    case buttonsOnly = 1
    case allGone = 2
    var id: Int { rawValue }
    var isFullscreen: Bool { self != .buttonsAndMenu }
    var title: String {
        switch self {
        case .buttonsAndMenu: AppText.localized("操作バーと評価ボタン")
        case .buttonsOnly: AppText.localized("評価ボタンのみ")
        case .allGone: AppText.localized("カードのみ")
        }
    }
}

/// AnkiDroid's answerButtonPosition values.
enum AnswerButtonPosition: String, CaseIterable, Identifiable {
    case top, bottom, none
    var id: String { rawValue }
    var title: String {
        switch self { case .top: AppText.localized("上"); case .bottom: AppText.localized("下"); case .none: AppText.localized("表示しない") }
    }
}
