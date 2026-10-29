import Foundation
#if os(iOS) || ANKIPAD_PARSE_UI
import SwiftUI
#endif

enum ReviewKey: String, CaseIterable, Identifiable {
    case space, enter, one, two, three, four, r, e, a, t, z, shiftZ, w, v, shiftV, shiftS, star
    case control1, control2, control3, control4, control5, control6, control7
    var id: String { rawValue }
    var title: String {
        switch self {
        case .space: "Space"; case .enter: "Return"
        case .one: "1"; case .two: "2"; case .three: "3"; case .four: "4"
        case .shiftZ: "Shift＋Z"; case .shiftV: "Shift＋V"; case .shiftS: "Shift＋S"; case .star: "*"
        default: rawValue.hasPrefix("control") ? "Ctrl＋" + String(rawValue.suffix(1)) : rawValue.uppercased()
        }
    }
    #if os(iOS) || ANKIPAD_PARSE_UI
    var shortcut: KeyboardShortcut {
        switch self {
        case .space: KeyboardShortcut(.space, modifiers: [])
        case .enter: KeyboardShortcut(.return, modifiers: [])
        case .one: KeyboardShortcut("1", modifiers: [])
        case .two: KeyboardShortcut("2", modifiers: [])
        case .three: KeyboardShortcut("3", modifiers: [])
        case .four: KeyboardShortcut("4", modifiers: [])
        case .shiftZ: KeyboardShortcut("z", modifiers: .shift)
        case .shiftV: KeyboardShortcut("v", modifiers: .shift)
        case .shiftS: KeyboardShortcut("s", modifiers: .shift)
        case .star: KeyboardShortcut("*", modifiers: [])
        default: KeyboardShortcut(KeyEquivalent(Character(String(rawValue.suffix(1)))), modifiers: rawValue.hasPrefix("control") ? .control : [])
        }
    }
    #endif
    var defaultAction: ReviewGestureAction {
        switch self {
        case .space, .enter: .flipOrGood
        case .one: .again; case .two: .hard; case .three: .good; case .four: .easy
        case .r: .replay; case .e: .edit; case .a: .add; case .t: .tags
        case .z: .undo; case .shiftZ: .redo; case .w: .whiteboard; case .v: .replayVoice; case .shiftV: .recordVoice; case .shiftS: .saveVoice; case .star: .mark
        case .control1: .flag1; case .control2: .flag2; case .control3: .flag3; case .control4: .flag4
        case .control5: .flag5; case .control6: .flag6; case .control7: .flag7
        }
    }
}
struct ReviewKeyboardConfiguration: Codable {
    var actions: [String: ReviewGestureAction] = [:]
    func action(for key: ReviewKey) -> ReviewGestureAction { actions[key.rawValue] ?? key.defaultAction }
    static func load(_ data: Data? = UserDefaults.standard.data(forKey: "reviewKeyboardConfiguration")) -> Self {
        guard let data, let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
}
#if os(iOS) || ANKIPAD_PARSE_UI
struct ReviewKeyboardSettingsView: View {
    @Binding var configuration: ReviewKeyboardConfiguration
    var body: some View {
        Form {
            Section(AppText.localized("キーの割り当て")) {
                ForEach(ReviewKey.allCases) { key in
                    Picker(key.title, selection: Binding(get: { configuration.action(for: key) }, set: { configuration.actions[key.rawValue] = $0 })) {
                        ForEach(ReviewGestureAction.allCases) { action in Text(action.title).tag(action) }
                    }
                }
            }
            Section {
                Text(AppText.localized("文字入力を求めるカードの表面では、Return以外の割り当てを停止します。編集画面やダイアログの表示中も停止します。"))
                Button(AppText.localized("初期設定に戻す")) { configuration = ReviewKeyboardConfiguration() }
            }
        }.studyThemeSurface().navigationTitle(AppText.localized("キーボードの割り当て"))
    }
}

#endif
