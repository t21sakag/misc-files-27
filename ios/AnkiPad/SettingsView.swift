import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: StudyModel
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: Any] = [:]
    @State private var loaded = false
    @State private var allowCollectionAPI = UserDefaults.standard.bool(forKey: "allowCollectionCardAPI")
    @State private var displayMode = ReviewDisplayMode(rawValue: UserDefaults.standard.integer(forKey: "reviewDisplayMode")) ?? .buttonsAndMenu
    @State private var showTopbar = UserDefaults.standard.object(forKey: "showReviewTopbar") as? Bool ?? true
    @State private var busy = false
    @State private var error: String?
    @State private var closeAfterAdd = UserDefaults.standard.object(forKey: "closeAfterAdd") as? Bool ?? false
    @State private var appearance: String = UserDefaults.standard.object(forKey: "appearance") as? String ?? "system"
    @State private var reviewZoom: Double = UserDefaults.standard.object(forKey: "reviewZoom") as? Double ?? 1.0
    @State private var keepScreenOn: Bool = UserDefaults.standard.object(forKey: "keepScreenOn") as? Bool ?? true
    @State private var gestureConfiguration = ReviewGestureConfiguration.load()
    @State private var keyboardConfiguration = ReviewKeyboardConfiguration.load()
    @State private var gamepadConfiguration = ReviewGamepadConfiguration.load()
    @State private var touchConfiguration = ReviewTouchConfiguration.load()
    @State private var toolbarConfiguration = ReviewToolbarConfiguration.load()
    @State private var swipeReview: Bool = UserDefaults.standard.object(forKey: "swipeReview") as? Bool ?? true
    @State private var keepWhiteboard: Bool = UserDefaults.standard.object(forKey: "keepWhiteboard") as? Bool ?? false
    var body: some View {
        NavigationStack {
            Form {
                if loaded {
                    Section("表示") {
                        Picker("学習画面の操作", selection: $displayMode) { ForEach(ReviewDisplayMode.allCases) { Text($0.title).tag($0) } }.accessibilityIdentifier("review-display-mode")
                        Toggle("学習の上部バーを表示", isOn: $showTopbar)
                        Text("全画面でも画面を3回タップすると操作バーを表示できます。").font(.caption).foregroundStyle(.secondary)
                        Picker("テーマ", selection: $appearance) { Text("システム").tag("system"); Text("ライト").tag("light"); Text("ダーク").tag("dark") }
                        VStack(alignment: .leading) { Text("カードの拡大率: \(Int(reviewZoom * 100))%"); Slider(value: $reviewZoom, in: 0.5...2.5, step: 0.05) }
                        Toggle("学習中は画面を消灯しない", isOn: $keepScreenOn)
                        Toggle("学習枚数を表示", isOn: boolean("reviewing", "showRemainingDueCounts"))
                        Toggle("評価ボタンに次回の間隔を表示", isOn: boolean("reviewing", "showIntervalsOnButtons"))
                    }
                    Section("学習操作") {
                        Toggle("スワイプで解答・評価", isOn: $swipeReview)
                        NavigationLink("スワイプの割り当て") { ReviewGestureSettingsView(configuration: $gestureConfiguration) }
                        NavigationLink("タッチ領域の割り当て") { ReviewTouchSettingsView(configuration: $touchConfiguration) }
                        NavigationLink("操作バーの設定") { ReviewToolbarSettingsView(configuration: $toolbarConfiguration) }
                        NavigationLink("キーボードの割り当て") { ReviewKeyboardSettingsView(configuration: $keyboardConfiguration) }
                        NavigationLink("ゲームパッドの割り当て") { ReviewGamepadSettingsView(configuration: $gamepadConfiguration) }
                        Toggle("次のカードにも手書きを残す", isOn: $keepWhiteboard)
                        Toggle("音声再生ボタンを隠す", isOn: boolean("reviewing", "hideAudioPlayButtons"))
                        Toggle("解答表示時に問題側の音声を止める", isOn: boolean("reviewing", "interruptAudioWhenAnswering"))
                    }
                    Section("スケジュール") {
                        Stepper("日付を切り替える時刻: \(integer("scheduling", "rollover").wrappedValue)時", value: integer("scheduling", "rollover"), in: 0...23)
                        Stepper("先取り学習: \(integer("scheduling", "learnAheadSecs").wrappedValue / 60)分", value: integer("scheduling", "learnAheadSecs"), in: 0...86400, step: 60)
                        Picker("新規と復習の順序", selection: string("scheduling", "newReviewMix", fallback: "DISTRIBUTE")) {
                            Text("混ぜる").tag("DISTRIBUTE"); Text("復習を先に").tag("REVIEWS_FIRST"); Text("新規を先に").tag("NEW_FIRST")
                        }
                        Toggle("学習負荷の分散", isOn: boolean("reviewing", "loadBalancerEnabled"))
                    }
                    Section("検索と編集") {
                        Toggle("追加後に編集画面を閉じる", isOn: $closeAfterAdd)
                        Toggle("検索でアクセントを区別しない", isOn: boolean("editing", "ignoreAccentsInSearch"))
                        Toggle("追加先を現在のデッキにする", isOn: boolean("editing", "addingDefaultsToCurrentDeck"))
                        Toggle("画像をPNGで取り込む", isOn: boolean("editing", "pasteImagesAsPng"))
                    }
                    Section { NavigationLink("ライセンスとソース") { OpenSourceLicensesView() } }
                    Section { NavigationLink("学習リマインダー") { ReviewReminderSettingsView(profile: model.currentProfile) } }
                    Section("カードのJavaScript権限") {
                        Toggle("全ノートの読み取り・タグ変更を許可", isOn: $allowCollectionAPI).accessibilityIdentifier("allow-collection-card-api")
                        Text("有効にすると、カード内のJavaScriptが現在のカード以外のノートの内容も読み取り、タグを変更できます。").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("バックアップの保持数") {
                        Stepper("日次: \(integer("backups", "daily").wrappedValue)", value: integer("backups", "daily"), in: 0...365)
                        Stepper("週次: \(integer("backups", "weekly").wrappedValue)", value: integer("backups", "weekly"), in: 0...104)
                        Stepper("月次: \(integer("backups", "monthly").wrappedValue)", value: integer("backups", "monthly"), in: 0...120)
                        Stepper("作成間隔: \(integer("backups", "minimumIntervalMins").wrappedValue)分", value: integer("backups", "minimumIntervalMins"), in: 0...1440)
                    }
                } else { ProgressView() }
            }
            .accessibilityIdentifier("settings-form")
            .disabled(busy)
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("保存") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            try await model.engine.savePreferences(values)
                            for (key, value) in ["appearance": appearance, "reviewZoom": reviewZoom, "keepScreenOn": keepScreenOn, "swipeReview": swipeReview, "keepWhiteboard": keepWhiteboard, "closeAfterAdd": closeAfterAdd] as [String: Any] { UserDefaults.standard.set(value, forKey: key) }
                            UserDefaults.standard.set(allowCollectionAPI, forKey: model.profilePreferenceKey("allowCollectionCardAPI"))
                            UserDefaults.standard.set(try JSONEncoder().encode(gestureConfiguration), forKey: "reviewGestureConfiguration")
                            UserDefaults.standard.set(try JSONEncoder().encode(keyboardConfiguration), forKey: "reviewKeyboardConfiguration")
                            UserDefaults.standard.set(try JSONEncoder().encode(gamepadConfiguration), forKey: "reviewGamepadConfiguration")
                            UserDefaults.standard.set(try JSONEncoder().encode(touchConfiguration), forKey: "reviewTouchConfiguration")
                            UserDefaults.standard.set(try JSONEncoder().encode(toolbarConfiguration), forKey: "reviewToolbarConfiguration")
                            model.reviewDisplayMode = displayMode
                            model.showReviewTopbar = showTopbar
                            model.refreshAfterEditing()
                            dismiss()
                        }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(!loaded || busy).accessibilityIdentifier("settings-save") }
            }
            .alert("保存できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
            .task { do { values = try await model.engine.preferences(); allowCollectionAPI = UserDefaults.standard.bool(forKey: model.profilePreferenceKey("allowCollectionCardAPI")); loaded = true } catch { self.error = error.localizedDescription } }
        }
    }
    private func boolean(_ group: String, _ key: String) -> Binding<Bool> {
        Binding(get: { (values[group] as? [String: Any])?[key] as? Bool ?? false }, set: { value in var section = values[group] as? [String: Any] ?? [:]; section[key] = value; values[group] = section })
    }
    private func integer(_ group: String, _ key: String) -> Binding<Int> {
        Binding(get: { (values[group] as? [String: Any])?[key] as? Int ?? 0 }, set: { value in var section = values[group] as? [String: Any] ?? [:]; section[key] = value; values[group] = section })
    }
    private func string(_ group: String, _ key: String, fallback: String) -> Binding<String> {
        Binding(get: { (values[group] as? [String: Any])?[key] as? String ?? fallback }, set: { value in var section = values[group] as? [String: Any] ?? [:]; section[key] = value; values[group] = section })
    }
}
