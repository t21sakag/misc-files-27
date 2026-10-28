import Foundation

enum ReviewDisplayMode: Int, CaseIterable, Identifiable {
    case buttonsAndMenu = 0
    case buttonsOnly = 1
    case allGone = 2
    var id: Int { rawValue }
    var isFullscreen: Bool { self != .buttonsAndMenu }
    var title: String {
        switch self {
        case .buttonsAndMenu: "操作バーと評価ボタン"
        case .buttonsOnly: "評価ボタンのみ"
        case .allGone: "カードのみ"
        }
    }
}

/// AnkiDroid's answerButtonPosition values.
enum AnswerButtonPosition: String, CaseIterable, Identifiable {
    case top, bottom, none
    var id: String { rawValue }
    var title: String {
        switch self { case .top: "上"; case .bottom: "下"; case .none: "表示しない" }
    }
}
