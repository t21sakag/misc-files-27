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
struct ReviewKeyboardConfiguration: Codable, Equatable {
    var actions: [String: ReviewGestureAction] = [:]
    func action(for key: ReviewKey) -> ReviewGestureAction { actions[key.rawValue] ?? key.defaultAction }
    static func load(_ data: Data? = UserDefaults.standard.data(forKey: "reviewKeyboardConfiguration")) -> Self {
        guard let data, let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
}

enum PreviewAction: String, Codable, CaseIterable, Identifiable {
    case none, previousCard, nextCard, toggleSide, backSideOnly, edit, replay, mark
    case flag0, flag1, flag2, flag3, flag4, flag5, flag6, flag7
    var id: String { rawValue }
    var title: String {
        if rawValue.hasPrefix("flag") {
            return rawValue == "flag0" ? AppText.localized("フラグを外す") : AppText.localized("フラグ ") + String(rawValue.dropFirst(4))
        }
        return [
            "none": AppText.localized("何もしない"),
            "previousCard": AppText.localized("前のカード"),
            "nextCard": AppText.localized("次のカード"),
            "toggleSide": AppText.localized("表裏を切り替え"),
            "backSideOnly": AppText.localized("裏面のみを切り替え"),
            "edit": AppText.localized("ノートを編集"),
            "replay": AppText.localized("音声を再生"),
            "mark": AppText.localized("マークを切り替え")
        ][rawValue] ?? rawValue
    }
}

enum PreviewKey: String, Codable, CaseIterable, Identifiable {
    case leftArrow, rightArrow, space, enter, b, e, r, star
    case control0, control1, control2, control3, control4, control5, control6, control7
    var id: String { rawValue }
    var title: String {
        switch self {
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .space: "Space"
        case .enter: "Return"
        case .star: "*"
        default:
            rawValue.hasPrefix("control") ? "Ctrl＋" + String(rawValue.suffix(1)) : rawValue.uppercased()
        }
    }
    #if os(iOS) || ANKIPAD_PARSE_UI
    var shortcut: KeyboardShortcut {
        switch self {
        case .leftArrow: KeyboardShortcut(.leftArrow, modifiers: [])
        case .rightArrow: KeyboardShortcut(.rightArrow, modifiers: [])
        case .space: KeyboardShortcut(.space, modifiers: [])
        case .enter: KeyboardShortcut(.return, modifiers: [])
        case .star: KeyboardShortcut("*", modifiers: [])
        default:
            KeyboardShortcut(KeyEquivalent(Character(String(rawValue.suffix(1)))), modifiers: rawValue.hasPrefix("control") ? .control : [])
        }
    }
    #endif
    var defaultAction: PreviewAction {
        switch self {
        case .leftArrow: .previousCard
        case .rightArrow: .nextCard
        case .space, .enter: .toggleSide
        case .b: .backSideOnly
        case .e: .edit
        case .r: .replay
        case .star: .mark
        case .control0: .flag0
        case .control1: .flag1
        case .control2: .flag2
        case .control3: .flag3
        case .control4: .flag4
        case .control5: .flag5
        case .control6: .flag6
        case .control7: .flag7
        }
    }
}

struct PreviewKeyboardConfiguration: Codable, Equatable {
    var actions: [String: PreviewAction] = [:]
    func action(for key: PreviewKey) -> PreviewAction { actions[key.rawValue] ?? key.defaultAction }
    func key(for target: PreviewAction) -> PreviewKey? {
        PreviewKey.allCases.first { action(for: $0) == target }
    }
    static func load(_ data: Data? = UserDefaults.standard.data(forKey: "previewKeyboardConfiguration")) -> Self {
        guard let data, let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
}

#if os(iOS) || ANKIPAD_PARSE_UI
struct ReviewKeyboardSettingsView: View {
    @Binding var configuration: ReviewKeyboardConfiguration
    var previewConfiguration: Binding<PreviewKeyboardConfiguration>? = nil
    var body: some View {
        Form {
            Section(AppText.localized("キーの割り当て")) {
                ForEach(ReviewKey.allCases) { key in
                    Picker(key.title, selection: Binding(get: { configuration.action(for: key) }, set: { configuration.actions[key.rawValue] = $0 })) {
                        ForEach(ReviewGestureAction.allCases) { action in Text(action.title).tag(action) }
                    }
                }
            }
            if let previewConfiguration {
                Section(AppText.localized("プレビューのキー割り当て")) {
                    ForEach(PreviewKey.allCases) { key in
                        Picker(key.title, selection: Binding(get: { previewConfiguration.wrappedValue.action(for: key) }, set: { previewConfiguration.wrappedValue.actions[key.rawValue] = $0 })) {
                            ForEach(PreviewAction.allCases) { action in Text(action.title).tag(action) }
                        }
                    }
                }
            }
            Section {
                Text(AppText.localized("文字入力を求めるカードの表面では、Return以外の割り当てを停止します。編集画面やダイアログの表示中も停止します。"))
                Button(AppText.localized("初期設定に戻す")) {
                    configuration = ReviewKeyboardConfiguration()
                    previewConfiguration?.wrappedValue = PreviewKeyboardConfiguration()
                }
            }
        }.studyThemeSurface().navigationTitle(AppText.localized("キーボードの割り当て"))
    }
}

#endif
