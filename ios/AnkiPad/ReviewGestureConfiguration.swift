import Foundation
#if os(iOS) || ANKIPAD_PARSE_UI
import SwiftUI
#endif

enum ReviewGestureAction: String, Codable, CaseIterable, Identifiable {
    case none, flipOrGood, flipOrAgain, showAnswer, again, hard, good, easy
    case replay, recordVoice, undo, redo, mark, edit, add, tags, bury, suspend
    case whiteboard, eraser, clearWhiteboard, autoAdvance, hint, allHints
    case flag0, flag1, flag2, flag3, flag4, flag5, flag6, flag7
    case user1, user2, user3, user4, user5, user6, user7, user8, user9
    var id: String { rawValue }
    var title: String {
        if rawValue.hasPrefix("user") { return "ユーザー操作 " + String(rawValue.dropFirst(4)) }
        if rawValue.hasPrefix("flag") { return rawValue == "flag0" ? "フラグを外す" : "フラグ " + String(rawValue.dropFirst(4)) }
        return ["none": "何もしない", "flipOrGood": "解答表示 / 普通", "flipOrAgain": "解答表示 / もう一度",
            "showAnswer": "解答を表示", "again": "もう一度", "hard": "難しい", "good": "普通", "easy": "簡単",
            "replay": "音声を再生", "recordVoice": "自分の声を録音・再生", "undo": "取り消す", "redo": "やり直す", "mark": "マークを切り替え",
            "edit": "ノートを編集", "add": "ノートを追加", "tags": "タグを編集", "bury": "今日は表示しない", "suspend": "保留",
            "whiteboard": "手書きを切り替え", "eraser": "消しゴムを切り替え", "clearWhiteboard": "手書きを消去",
            "autoAdvance": "自動進行を切り替え", "hint": "次のヒントを表示", "allHints": "すべてのヒントを表示"][rawValue] ?? rawValue
    }
}
struct ReviewGestureConfiguration: Codable {
    var left: ReviewGestureAction = .flipOrGood
    var right: ReviewGestureAction = .flipOrAgain
    var up: ReviewGestureAction = .none
    var down: ReviewGestureAction = .none
    var distance: Double = 60
    var minimumDistance: Double { distance.isFinite ? min(180, max(20, distance)) : 60 }
    static func load(_ data: Data? = UserDefaults.standard.data(forKey: "reviewGestureConfiguration")) -> Self {
        guard let data, let config = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return config
    }
    func action(x: Double, y: Double) -> ReviewGestureAction {
        guard max(abs(x), abs(y)) >= minimumDistance else { return .none }
        if abs(x) > abs(y) * 1.5 { return x < 0 ? left : right }
        if abs(y) > abs(x) * 1.5 { return y < 0 ? up : down }
        return .none
    }
}
#if os(iOS) || ANKIPAD_PARSE_UI
struct ReviewGestureSettingsView: View {
    @Binding var configuration: ReviewGestureConfiguration
    var body: some View {
        Form {
            Section("スワイプ操作") {
                actionPicker("左", value: $configuration.left)
                actionPicker("右", value: $configuration.right)
                actionPicker("上", value: $configuration.up)
                actionPicker("下", value: $configuration.down)
            }
            Section("スワイプの距離") {
                Text("\(Int(configuration.minimumDistance))ポイント")
                Slider(value: $configuration.distance, in: 20...180, step: 10)
            }
            Section {
                Text("手書き中はスワイプ操作を停止します。評価だけを割り当てた操作は、解答表示後に使えます。画面を3回タップすると全画面表示を解除できます。")
                Button("初期設定に戻す") { configuration = ReviewGestureConfiguration() }
            }
        }.navigationTitle("スワイプの割り当て")
    }
    private func actionPicker(_ title: String, value: Binding<ReviewGestureAction>) -> some View {
        Picker(title, selection: value) { ForEach(ReviewGestureAction.allCases) { Text($0.title).tag($0) } }
    }
}

#endif
