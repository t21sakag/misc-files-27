import Foundation
#if os(iOS) || ANKIPAD_PARSE_UI
import SwiftUI
#endif

struct ReviewTouchConfiguration: Codable {
    var enabled = false
    var question: [String: ReviewGestureAction] = [:]
    var answer: [String: ReviewGestureAction] = [:]
    func action(x: Double, y: Double, revealed: Bool) -> ReviewGestureAction {
        guard enabled, x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else { return .none }
        let zone = min(2, Int(y * 3)) * 3 + min(2, Int(x * 3))
        return (revealed ? answer : question)[String(zone)] ?? .none
    }
    static func load(_ data: Data? = UserDefaults.standard.data(forKey: "reviewTouchConfiguration")) -> Self {
        guard let data, let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
}
#if os(iOS) || ANKIPAD_PARSE_UI
struct ReviewTouchSettingsView: View {
    @Binding var configuration: ReviewTouchConfiguration
    @State private var answer = false
    var body: some View {
        Form {
            Toggle("タッチ領域を使う", isOn: $configuration.enabled)
            Picker("カードの面", selection: $answer) { Text("表面").tag(false); Text("裏面").tag(true) }.pickerStyle(.segmented)
            Section("カードを3×3に分けた領域") {
                ForEach(0..<9, id: \.self) { zone in
                    Picker(["上・左", "上・中央", "上・右", "中央・左", "中央", "中央・右", "下・左", "下・中央", "下・右"][zone], selection: Binding(get: {
                        (answer ? configuration.answer : configuration.question)[String(zone)] ?? .none
                    }, set: { value in
                        if answer { configuration.answer[String(zone)] = value }
                        else { configuration.question[String(zone)] = value }
                    })) {
                        ForEach(ReviewGestureAction.allCases) { action in Text(action.title).tag(action) }
                    }
                }
            }
            Section {
                Text("リンクや入力欄、ボタンのタップ、文字選択、手書き中は領域操作を行いません。3回タップと区別するため少し待ってから実行します。")
                Button("初期設定に戻す") { configuration = ReviewTouchConfiguration() }
            }
        }.navigationTitle("タッチ領域の割り当て")
    }
}

#endif
