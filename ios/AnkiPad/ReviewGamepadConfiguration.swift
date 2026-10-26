import Foundation
#if os(iOS) || ANKIPAD_PARSE_UI
import SwiftUI
#endif

enum ReviewGamepadButton: String, CaseIterable, Identifiable {
    case a, b, x, y, up, down, left, right, leftShoulder, rightShoulder, leftTrigger, rightTrigger
    var id: String { rawValue }
    var title: String {
        ["a": "A / 下", "b": "B / 右", "x": "X / 左", "y": "Y / 上", "up": "方向キー 上", "down": "方向キー 下",
         "left": "方向キー 左", "right": "方向キー 右", "leftShoulder": "L1", "rightShoulder": "R1", "leftTrigger": "L2", "rightTrigger": "R2"][rawValue] ?? rawValue
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
            Toggle("ゲームパッドで学習", isOn: $configuration.enabled)
            Section("ボタンの割り当て") {
                ForEach(ReviewGamepadButton.allCases) { button in
                    Picker(button.title, selection: Binding(get: { configuration.action(for: button) }, set: { configuration.actions[button.rawValue] = $0 })) {
                        ForEach(ReviewGestureAction.allCases) { action in Text(action.title).tag(action) }
                    }
                }
            }
            Section {
                Text("iPadの設定で接続した対応コントローラーを使います。機種によってボタンの名前が異なります。")
                Button("初期設定に戻す") { configuration = ReviewGamepadConfiguration() }
            }
        }.navigationTitle("ゲームパッドの割り当て")
    }
}

#endif
