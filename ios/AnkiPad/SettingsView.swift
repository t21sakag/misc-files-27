import SwiftUI
import AVFoundation

struct SettingsView: View {
    @ObservedObject var model: StudyModel
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: Any] = [:]
    @State private var loaded = false
    @State private var language = AppLanguageChoice.load()
    @State private var automaticSync = true
    @State private var networkPreferences = SyncNetworkPreferences.load()
    @State private var confirmingOneWaySync = false
    @State private var automaticTTS = false
    @State private var allowCollectionAPI = UserDefaults.standard.bool(forKey: "allowCollectionCardAPI")
    @State private var allowCardExternalLaunch = UserDefaults.standard.bool(forKey: "allowCardExternalLaunch")
    @State private var allowTemplateAudioRecording = UserDefaults.standard.bool(forKey: CardTemplateAudioCapture.preferenceKey)
    @State private var displayMode = ReviewDisplayMode(rawValue: UserDefaults.standard.integer(forKey: "reviewDisplayMode")) ?? .buttonsAndMenu
    @State private var showTopbar = UserDefaults.standard.object(forKey: "showReviewTopbar") as? Bool ?? true
    @State private var imageZoom = UserDefaults.standard.object(forKey: "imageZoom") as? Int ?? 100
    @State private var centerVertically = UserDefaults.standard.bool(forKey: "centerVertically")
    @State private var showDeckTitle = UserDefaults.standard.bool(forKey: "showDeckTitle")
    @State private var showETA = UserDefaults.standard.bool(forKey: "showETA")
    @State private var autoFocusTypeInAnswer = UserDefaults.standard.object(forKey: "autoFocusTypeInAnswer") as? Bool ?? true
    @State private var browserFontPercent = UserDefaults.standard.object(forKey: "relativeCardBrowserFontSize") as? Int ?? 100
    @State private var browserMediaFilenames = UserDefaults.standard.bool(forKey: "card_browser_show_media_filenames")
    @State private var answerHoldMilliseconds = String(UserDefaults.standard.object(forKey: "showCardAnswerButtonTime") as? Int ?? 0)
    @State private var buttonIntervalMilliseconds = String(UserDefaults.standard.object(forKey: "doubleTapTimeout") as? Int ?? 200)
    @State private var answerPosition = AnswerButtonPosition(rawValue: UserDefaults.standard.string(forKey: "answerButtonPosition") ?? "bottom") ?? .bottom
    @State private var answerSize = Double(UserDefaults.standard.object(forKey: "answerButtonSize") as? Int ?? 100)
    @State private var largeAnswerButtons = UserDefaults.standard.bool(forKey: "showLargeAnswerButtons")
    @State private var busy = false
    @State private var error: String?
    @State private var closeAfterAdd = UserDefaults.standard.object(forKey: "closeAfterAdd") as? Bool ?? false
    @State private var appearance: String = UserDefaults.standard.object(forKey: "appearance") as? String ?? "system"
    @State private var dayTheme = StudyDayTheme(rawValue: UserDefaults.standard.string(forKey: "dayTheme") ?? "1") ?? .light
    @State private var nightTheme = StudyNightTheme(rawValue: UserDefaults.standard.string(forKey: "nightTheme") ?? "3") ?? .black
    @State private var removeAnimations = UserDefaults.standard.bool(forKey: "safeDisplay")
    @State private var deckBackgroundChange = DeckBackgroundChange.unchanged
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
                    Section(AppText.localized("アプリの言語")) {
                        Picker(AppText.localized("言語"), selection: $language) {
                            ForEach(AppLanguageChoice.allCases) { Text($0.title).tag($0) }
                        }.accessibilityIdentifier("app-language")
                        Text(AppText.localized("保存後、アプリを終了して開き直すと適用します。同期や編集中のデータはそのままです。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section(AppText.localized("同期")) {
                        Toggle(AppText.localized("自動同期"), isOn: $automaticSync).accessibilityIdentifier("automatic-sync")
                        Text(AppText.localized("起動・前面復帰時とバックグラウンド移行時に同期します。全体を置き換える同期には確認が必要です。未保存の編集がある間は待機します。"))
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle(AppText.localized("従量課金の回線でも同期する"), isOn: $networkPreferences.allowMetered).accessibilityIdentifier("sync-allow-metered")
                        Picker(AppText.localized("画像・音声の取得"), selection: $networkPreferences.mediaFetch) {
                            ForEach(SyncMediaFetch.allCases) { Text($0.title).tag($0) }
                        }.accessibilityIdentifier("sync-media-fetch")
                        Toggle(AppText.localized("未同期の変更を表示"), isOn: $networkPreferences.showStatusBadge).accessibilityIdentifier("sync-status-badge")
                        Stepper(AppText.localized("通信のタイムアウト: \(networkPreferences.ioTimeoutSecs)秒"), value: $networkPreferences.ioTimeoutSecs,
                                in: SyncNetworkPreferences.minimumTimeout...SyncNetworkPreferences.maximumTimeout, step: 10)
                            .accessibilityIdentifier("sync-timeout")
                        Button(AppText.localized("次回の同期を一方向にする")) { confirmingOneWaySync = true }
                            .disabled(busy || model.isSyncing).accessibilityIdentifier("sync-force-one-way")
                    }
                    Section(AppText.localized("学習時間")) {
                        Stepper(AppText.localized("学習の区切り: \(timeboxMinutes.wrappedValue)分（0で無効）"), value: timeboxMinutes, in: 0...120)
                            .accessibilityIdentifier("timebox-limit")
                        Text(AppText.localized("指定時間を過ぎてカードに回答したときに、回答枚数を知らせます。続行か終了を選べます。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section(AppText.localized("表示")) {
                        Picker(AppText.localized("学習画面の操作"), selection: $displayMode) { ForEach(ReviewDisplayMode.allCases) { Text($0.title).tag($0) } }.accessibilityIdentifier("review-display-mode")
                        Toggle(AppText.localized("学習の上部バーを表示"), isOn: $showTopbar)
                        Toggle(AppText.localized("学習中にデッキ名を表示"), isOn: $showDeckTitle).accessibilityIdentifier("show-deck-title")
                        Toggle(AppText.localized("学習の残り時間を表示"), isOn: $showETA).accessibilityIdentifier("show-review-eta")
                        Text(AppText.localized("全画面でも画面を3回タップすると操作バーを表示できます。")).font(.caption).foregroundStyle(.secondary)
                        Picker(AppText.localized("テーマ"), selection: $appearance) { Text(AppText.localized("システム")).tag("system"); Text(AppText.localized("ライト")).tag("light"); Text(AppText.localized("ダーク")).tag("dark") }.accessibilityIdentifier("app-theme-mode")
                        Picker(AppText.localized("昼のテーマ"), selection: $dayTheme) {
                            ForEach(StudyDayTheme.allCases) { Text($0.title).tag($0) }
                        }.accessibilityIdentifier("day-theme")
                        Picker(AppText.localized("夜のテーマ"), selection: $nightTheme) {
                            ForEach(StudyNightTheme.allCases) { Text($0.title).tag($0) }
                        }.accessibilityIdentifier("night-theme")
                        Toggle(AppText.localized("アプリのアニメーションを無効にする"), isOn: $removeAnimations).accessibilityIdentifier("remove-app-animations")
                        Text(AppText.localized("iPadの「視差効果を減らす」やE Inkテーマが有効な場合も、アプリの画面遷移を抑制します。"))
                            .font(.caption).foregroundStyle(.secondary)
                        NavigationLink(AppText.localized("デッキ一覧の背景")) {
                            DeckBackgroundSettingsView(root: model.engine.root, change: $deckBackgroundChange)
                        }.accessibilityIdentifier("deck-background-open")
                        VStack(alignment: .leading) { Text(AppText.localized("カードの拡大率: \(String(Int(reviewZoom * 100)) + "%")")); Slider(value: $reviewZoom, in: 0.5...2.5, step: 0.05) }
                        Stepper(AppText.localized("画像の拡大率: \(String(imageZoom) + "%")"), value: $imageZoom, in: 50...300, step: 10)
                            .accessibilityIdentifier("image-zoom")
                        Toggle(AppText.localized("カード内容を上下の中央に表示"), isOn: $centerVertically).accessibilityIdentifier("center-vertically")
                        Toggle(AppText.localized("学習中は画面を消灯しない"), isOn: $keepScreenOn)
                        Toggle(AppText.localized("学習枚数を表示"), isOn: boolean("reviewing", "showRemainingDueCounts"))
                        Toggle(AppText.localized("評価ボタンに次回の間隔を表示"), isOn: boolean("reviewing", "showIntervalsOnButtons"))
                    }
                    Section(AppText.localized("評価ボタン")) {
                        Picker(AppText.localized("表示位置"), selection: $answerPosition) {
                            ForEach(AnswerButtonPosition.allCases) { Text($0.title).tag($0) }
                        }.accessibilityIdentifier("answer-position")
                        Toggle(AppText.localized("大きな評価ボタン（2行）"), isOn: $largeAnswerButtons).accessibilityIdentifier("answer-large")
                        Text(AppText.localized("ボタンの大きさ: \(String(Int(answerSize)) + "%")"))
                        Slider(value: $answerSize, in: 10...200, step: 10).accessibilityIdentifier("answer-size")
                        Text(AppText.localized("非表示でも、設定済みのスワイプ・タッチ領域・キーボードで解答できます。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section(AppText.localized("ブラウザの表示")) {
                        Stepper(AppText.localized("文字サイズ: \(String(browserFontPercent) + "%")"), value: $browserFontPercent, in: 10...200, step: 10)
                            .accessibilityIdentifier("browser-font-size")
                        Toggle(AppText.localized("音声ファイル名を表示"), isOn: $browserMediaFilenames).accessibilityIdentifier("browser-media-filenames")
                    }
                    Section(AppText.localized("音声")) {
                        Toggle(AppText.localized("音声がないカードを読み上げる"), isOn: $automaticTTS).accessibilityIdentifier("tts-enabled")
                        Text(AppText.localized("学習画面の「読み上げ音声を選択」から、デッキとカードの面に合わせて音声を選べます。"))
                    }
                    Section(AppText.localized("学習操作")) {
                        LabeledContent(AppText.localized("解答表示の長押し（ミリ秒）")) {
                            TextField("0〜2000", text: $answerHoldMilliseconds).keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing).frame(width: 100).accessibilityIdentifier("answer-hold-time")
                        }
                        LabeledContent(AppText.localized("ボタンの連打防止（ミリ秒）")) {
                            TextField("0〜1000", text: $buttonIntervalMilliseconds).keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing).frame(width: 100).accessibilityIdentifier("review-button-interval")
                        }
                        Text(AppText.localized("長押し時間を0にすると通常のタップで解答を表示します。連打防止は解答表示・評価ボタンの誤操作を防ぎます。"))
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle(AppText.localized("入力式カードの解答欄に自動フォーカス"), isOn: $autoFocusTypeInAnswer).accessibilityIdentifier("auto-focus-type-answer")
                        Toggle(AppText.localized("スワイプで解答・評価"), isOn: $swipeReview)
                        NavigationLink(AppText.localized("スワイプの割り当て")) { ReviewGestureSettingsView(configuration: $gestureConfiguration) }
                        NavigationLink(AppText.localized("タッチ領域の割り当て")) { ReviewTouchSettingsView(configuration: $touchConfiguration) }.accessibilityIdentifier("touch-settings-open")
                        NavigationLink(AppText.localized("操作バーの設定")) { ReviewToolbarSettingsView(configuration: $toolbarConfiguration) }.accessibilityIdentifier("toolbar-settings-open")
                        NavigationLink(AppText.localized("キーボードの割り当て")) { ReviewKeyboardSettingsView(configuration: $keyboardConfiguration) }
                        NavigationLink(AppText.localized("ゲームパッドの割り当て")) { ReviewGamepadSettingsView(configuration: $gamepadConfiguration) }
                        Toggle(AppText.localized("次のカードにも手書きを残す"), isOn: $keepWhiteboard)
                        Toggle(AppText.localized("音声再生ボタンを隠す"), isOn: boolean("reviewing", "hideAudioPlayButtons"))
                        Toggle(AppText.localized("解答表示時に問題側の音声を止める"), isOn: boolean("reviewing", "interruptAudioWhenAnswering"))
                    }
                    Section(AppText.localized("スケジュール")) {
                        Stepper(AppText.localized("日付を切り替える時刻: \(integer("scheduling", "rollover").wrappedValue)時"), value: integer("scheduling", "rollover"), in: 0...23)
                        Stepper(AppText.localized("先取り学習: \(integer("scheduling", "learnAheadSecs").wrappedValue / 60)分"), value: integer("scheduling", "learnAheadSecs"), in: 0...86400, step: 60)
                        Picker(AppText.localized("新規と復習の順序"), selection: string("scheduling", "newReviewMix", fallback: "DISTRIBUTE")) {
                            Text(AppText.localized("混ぜる")).tag("DISTRIBUTE"); Text(AppText.localized("復習を先に")).tag("REVIEWS_FIRST"); Text(AppText.localized("新規を先に")).tag("NEW_FIRST")
                        }
                        Toggle(AppText.localized("学習負荷の分散"), isOn: boolean("reviewing", "loadBalancerEnabled"))
                    }
                    Section(AppText.localized("検索と編集")) {
                        Toggle(AppText.localized("追加後に編集画面を閉じる"), isOn: $closeAfterAdd)
                        Toggle(AppText.localized("検索でアクセントを区別しない"), isOn: boolean("editing", "ignoreAccentsInSearch"))
                        Toggle(AppText.localized("追加先を現在のデッキにする"), isOn: boolean("editing", "addingDefaultsToCurrentDeck"))
                        Toggle(AppText.localized("画像をPNGで取り込む"), isOn: boolean("editing", "pasteImagesAsPng"))
                    }
                    Section { NavigationLink(AppText.localized("ライセンスとソース")) { OpenSourceLicensesView() } }
                    Section { NavigationLink(AppText.localized("学習リマインダー")) { ReviewReminderSettingsView(profile: model.currentProfile, engine: model.engine, decks: model.decks) }.accessibilityIdentifier("reminder-open") }
                    Section(AppText.localized("カードのJavaScript権限")) {
                        Toggle(AppText.localized("テンプレートからマイク録音を許可"), isOn: $allowTemplateAudioRecording).accessibilityIdentifier("allow-template-audio-recording")
                        Text(AppText.localized("有効にして保存すると、iPadOSのマイク許可も確認します。カメラへのアクセスは許可しません。"))
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle(AppText.localized("カードから外部アプリを開く"), isOn: $allowCardExternalLaunch).accessibilityIdentifier("allow-card-external-launch")
                        Text(AppText.localized("通常のWebリンクはこの設定に関係なく開けます。別のアプリを起動するリンクは、許可した場合だけ開きます。"))
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle(AppText.localized("全ノートの読み取り・タグ変更を許可"), isOn: $allowCollectionAPI).accessibilityIdentifier("allow-collection-card-api")
                        Text(AppText.localized("有効にすると、カード内のJavaScriptが現在のカード以外のノートの内容も読み取り、タグを変更できます。")).font(.caption).foregroundStyle(.secondary)
                    }
                    Section(AppText.localized("バックアップの保持数")) {
                        Stepper(AppText.localized("日次: \(integer("backups", "daily").wrappedValue)"), value: integer("backups", "daily"), in: 0...365)
                        Stepper(AppText.localized("週次: \(integer("backups", "weekly").wrappedValue)"), value: integer("backups", "weekly"), in: 0...104)
                        Stepper(AppText.localized("月次: \(integer("backups", "monthly").wrappedValue)"), value: integer("backups", "monthly"), in: 0...120)
                        Stepper(AppText.localized("作成間隔: \(integer("backups", "minimumIntervalMins").wrappedValue)分"), value: integer("backups", "minimumIntervalMins"), in: 0...1440)
                    }
                } else { ProgressView() }
            }
            .accessibilityIdentifier("settings-form")
            .studyThemeSurface()
            .disabled(busy)
            .navigationTitle(AppText.localized("設定"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppText.localized("キャンセル")) { dismiss() }.disabled(busy).accessibilityIdentifier("settings-cancel") }
                ToolbarItem(placement: .confirmationAction) { Button(AppText.localized("保存")) {
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            guard let hold = Int(answerHoldMilliseconds.trimmingCharacters(in: .whitespacesAndNewlines)), (0...2000).contains(hold),
                                  let interval = Int(buttonIntervalMilliseconds.trimmingCharacters(in: .whitespacesAndNewlines)), (0...1000).contains(interval) else {
                                throw EngineError(message: AppText.localized("長押し時間は0〜2000、連打防止は0〜1000の整数を入力してください（ミリ秒）。"))
                            }
                            if allowTemplateAudioRecording {
                                guard await AVAudioApplication.requestRecordPermission() else {
                                    throw EngineError(message: AppText.localized("マイクの使用が許可されていません。iPadの設定でマイクの許可を確認してください。"))
                                }
                            }
                            try await model.engine.savePreferences(values)
                            try await DeckBackgroundStore.shared.save(deckBackgroundChange, root: model.engine.root)
                            for (key, value) in ["appearance": appearance, "reviewZoom": reviewZoom, "keepScreenOn": keepScreenOn, "swipeReview": swipeReview, "keepWhiteboard": keepWhiteboard, "closeAfterAdd": closeAfterAdd] as [String: Any] { UserDefaults.standard.set(value, forKey: key) }
                            UserDefaults.standard.set(allowCollectionAPI, forKey: model.profilePreferenceKey("allowCollectionCardAPI"))
                            UserDefaults.standard.set(allowCardExternalLaunch, forKey: "allowCardExternalLaunch")
                            UserDefaults.standard.set(allowTemplateAudioRecording, forKey: CardTemplateAudioCapture.preferenceKey)
                            UserDefaults.standard.set(try JSONEncoder().encode(gestureConfiguration), forKey: "reviewGestureConfiguration")
                            UserDefaults.standard.set(try JSONEncoder().encode(keyboardConfiguration), forKey: "reviewKeyboardConfiguration")
                            UserDefaults.standard.set(try JSONEncoder().encode(gamepadConfiguration), forKey: "reviewGamepadConfiguration")
                            UserDefaults.standard.set(try JSONEncoder().encode(touchConfiguration), forKey: "reviewTouchConfiguration")
                            UserDefaults.standard.set(try JSONEncoder().encode(toolbarConfiguration), forKey: "reviewToolbarConfiguration")
                            model.reviewDisplayMode = displayMode
                            model.showReviewTopbar = showTopbar
                            UserDefaults.standard.set(answerPosition.rawValue, forKey: "answerButtonPosition")
                            UserDefaults.standard.set(Int(answerSize), forKey: "answerButtonSize")
                            UserDefaults.standard.set(largeAnswerButtons, forKey: "showLargeAnswerButtons")
                            UserDefaults.standard.set(imageZoom, forKey: "imageZoom")
                            UserDefaults.standard.set(centerVertically, forKey: "centerVertically")
                            UserDefaults.standard.set(showDeckTitle, forKey: "showDeckTitle")
                            UserDefaults.standard.set(showETA, forKey: "showETA")
                            UserDefaults.standard.set(autoFocusTypeInAnswer, forKey: "autoFocusTypeInAnswer")
                            UserDefaults.standard.set(browserFontPercent, forKey: "relativeCardBrowserFontSize")
                            UserDefaults.standard.set(browserMediaFilenames, forKey: "card_browser_show_media_filenames")
                            UserDefaults.standard.set(hold, forKey: "showCardAnswerButtonTime")
                            UserDefaults.standard.set(interval, forKey: "doubleTapTimeout")
                            UserDefaults.standard.set(dayTheme.rawValue, forKey: "dayTheme")
                            UserDefaults.standard.set(nightTheme.rawValue, forKey: "nightTheme")
                            UserDefaults.standard.set(removeAnimations, forKey: "safeDisplay")
                            networkPreferences.save()
                            model.setAutomaticSyncEnabled(automaticSync)
                            ReviewSpeechPreferences.setEnabled(automaticTTS, profileID: model.currentProfileID)
                            language.save()
                            model.refreshAfterEditing()
                            dismiss()
                        }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(!loaded || busy).accessibilityIdentifier("settings-save") }
            }
            .alert(AppText.localized("次回の同期を一方向にしますか？"), isPresented: $confirmingOneWaySync) {
                Button(AppText.localized("一方向にする"), role: .destructive) {
                    busy = true
                    Task {
                        defer { busy = false }
                        do { try await model.forceOneWaySync() } catch { self.error = error.localizedDescription }
                    }
                }.accessibilityIdentifier("sync-force-one-way-confirm")
                Button(AppText.localized("キャンセル"), role: .cancel) {}
            } message: { Text(AppText.localized("次の同期では、AnkiWebとこのiPadのどちらかのコレクション全体を選んで、もう一方を置き換えます。選ばなかった側だけの変更は失われます。")) }
            .alert(AppText.localized("保存できませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
            .task { do { values = try await model.engine.preferences(); automaticSync = model.automaticSyncEnabled; automaticTTS = ReviewSpeechPreferences.enabled(profileID: model.currentProfileID); allowCollectionAPI = UserDefaults.standard.bool(forKey: model.profilePreferenceKey("allowCollectionCardAPI")); loaded = true } catch { self.error = error.localizedDescription } }
        }
    }
    private var timeboxMinutes: Binding<Int> {
        Binding(get: { ((values["reviewing"] as? [String: Any])?["timeLimitSecs"] as? Int ?? 0) / 60 }, set: { minutes in
            var section = values["reviewing"] as? [String: Any] ?? [:]
            section["timeLimitSecs"] = minutes * 60
            values["reviewing"] = section
        })
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
