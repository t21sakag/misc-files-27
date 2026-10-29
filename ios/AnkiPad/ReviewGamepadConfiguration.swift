import Foundation
#if os(iOS) || ANKIPAD_PARSE_UI
import SwiftUI
#endif

enum ReviewGamepadButton: String, CaseIterable, Identifiable {
    case a, b, x, y, up, down, left, right, leftShoulder, rightShoulder, leftTrigger, rightTrigger
    var id: String { rawValue }
    var title: String {
        ["a": AppText.localized("A / 下"), "b": AppText.localized("B / 右"), "x": AppText.localized("X / 左"), "y": AppText.localized("Y / 上"), "up": AppText.localized("方向キー 上"), "down": AppText.localized("方向キー 下"),
         "left": AppText.localized("方向キー 左"), "right": AppText.localized("方向キー 右"), "leftShoulder": "L1", "rightShoulder": "R1", "leftTrigger": "L2", "rightTrigger": "R2"][rawValue] ?? rawValue
    }
    var defaultAction: ReviewGestureAction {
        switch self {
        case .a: .flipOrGood; case .b: .flipOrAgain; case .x: .hard; case .y: .easy
        case .leftShoulder: .undo; case .rightShoulder: .replay
        default: .none
        }
    }
}
struct ReviewGamepadConfiguration: Codable {
    var enabled = false
    var actions: [String: ReviewGestureAction] = [:]
    func action(for button: ReviewGamepadButton) -> ReviewGestureAction { actions[button.rawValue] ?? button.defaultAction }
    static func load(_ data: Data? = UserDefaults.standard.data(forKey: "reviewGamepadConfiguration")) -> Self {
        guard let data, let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
}
#if os(iOS) || ANKIPAD_PARSE_UI
struct ReviewGamepadSettingsView: View {
    @Binding var configuration: ReviewGamepadConfiguration
    var body: some View {
        Form {
            Toggle(AppText.localized("ゲームパッドで学習"), isOn: $configuration.enabled)
            Section(AppText.localized("ボタンの割り当て")) {
                ForEach(ReviewGamepadButton.allCases) { button in
                    Picker(button.title, selection: Binding(get: { configuration.action(for: button) }, set: { configuration.actions[button.rawValue] = $0 })) {
                        ForEach(ReviewGestureAction.allCases) { action in Text(action.title).tag(action) }
                    }
                }
            }
            Section {
                Text(AppText.localized("iPadの設定で接続した対応コントローラーを使います。機種によってボタンの名前が異なります。"))
                Button(AppText.localized("初期設定に戻す")) { configuration = ReviewGamepadConfiguration() }
            }
        }.studyThemeSurface().navigationTitle(AppText.localized("ゲームパッドの割り当て"))
    }
}

#endif
