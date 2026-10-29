import Foundation
#if os(iOS) || ANKIPAD_PARSE_UI
import SwiftUI
#endif

enum ReviewGestureAction: String, Codable, CaseIterable, Identifiable {
    case none, flipOrGood, flipOrAgain, showAnswer, again, hard, good, easy
    case replay, recordVoice, replayVoice, saveVoice, selectTTS, undo, redo, mark, edit, add, tags, bury, suspend
    case whiteboard, eraser, clearWhiteboard, penColor, autoAdvance, hint, allHints
    case flag0, flag1, flag2, flag3, flag4, flag5, flag6, flag7
    case user1, user2, user3, user4, user5, user6, user7, user8, user9
    var id: String { rawValue }
    var title: String {
        if rawValue.hasPrefix("user") { return AppText.localized("ユーザー操作 ") + String(rawValue.dropFirst(4)) }
        if rawValue.hasPrefix("flag") { return rawValue == "flag0" ? AppText.localized("フラグを外す") : AppText.localized("フラグ ") + String(rawValue.dropFirst(4)) }
        return ["none": AppText.localized("何もしない"), "flipOrGood": AppText.localized("解答表示 / 普通"), "flipOrAgain": AppText.localized("解答表示 / もう一度"),
            "showAnswer": AppText.localized("解答を表示"), "again": AppText.localized("もう一度"), "hard": AppText.localized("難しい"), "good": AppText.localized("普通"), "easy": AppText.localized("簡単"),
            "replay": AppText.localized("音声を再生"), "recordVoice": AppText.localized("自分の声を録音"), "replayVoice": AppText.localized("自分の声を再生・一時停止"), "saveVoice": AppText.localized("録音を停止して保持"), "selectTTS": AppText.localized("読み上げ音声を選択"), "undo": AppText.localized("取り消す"), "redo": AppText.localized("やり直す"), "mark": AppText.localized("マークを切り替え"),
            "edit": AppText.localized("ノートを編集"), "add": AppText.localized("ノートを追加"), "tags": AppText.localized("タグを編集"), "bury": AppText.localized("今日は表示しない"), "suspend": AppText.localized("保留"),
            "whiteboard": AppText.localized("手書きを切り替え"), "eraser": AppText.localized("消しゴムを切り替え"), "clearWhiteboard": AppText.localized("手書きを消去"), "penColor": AppText.localized("ペンの色を変更"),
            "autoAdvance": AppText.localized("自動進行を切り替え"), "hint": AppText.localized("次のヒントを表示"), "allHints": AppText.localized("すべてのヒントを表示")][rawValue] ?? rawValue
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
            Section(AppText.localized("スワイプ操作")) {
                actionPicker(AppText.localized("左"), value: $configuration.left)
                actionPicker(AppText.localized("右"), value: $configuration.right)
                actionPicker(AppText.localized("上"), value: $configuration.up)
                actionPicker(AppText.localized("下"), value: $configuration.down)
            }
            Section(AppText.localized("スワイプの距離")) {
                Text(AppText.localized("\(Int(configuration.minimumDistance))ポイント"))
                Slider(value: $configuration.distance, in: 20...180, step: 10)
            }
            Section {
                Text(AppText.localized("手書き中はスワイプ操作を停止します。評価だけを割り当てた操作は、解答表示後に使えます。画面を3回タップすると全画面表示を解除できます。"))
                Button(AppText.localized("初期設定に戻す")) { configuration = ReviewGestureConfiguration() }
            }
        }.studyThemeSurface().navigationTitle(AppText.localized("スワイプの割り当て"))
    }
    private func actionPicker(_ title: String, value: Binding<ReviewGestureAction>) -> some View {
        Picker(title, selection: value) { ForEach(ReviewGestureAction.allCases) { Text($0.title).tag($0) } }
    }
}

#endif
