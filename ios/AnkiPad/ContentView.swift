import SwiftUI
import UniformTypeIdentifiers
import PencilKit
import UIKit

private enum ReviewerPanelAction: String, CaseIterable, Identifiable {
    case edit, add, tags, due, reset, info, mark, suspend, suspendNote, bury, buryNote, undo, redo, replay, voice, speech, whiteboard
    var id: String { rawValue }
    var title: String {
        switch self {
        case .edit: "ノートを編集"; case .add: "ノートを追加"; case .tags: "タグを編集"
        case .due: "期日を変更"; case .reset: "新規カードに戻す"; case .info: "カード情報"
        case .mark: "マークを切り替え"; case .suspend: "カードを保留"; case .suspendNote: "関連カードを保留"
        case .bury: "カードを今日は表示しない"; case .buryNote: "関連カードを今日は表示しない"
        case .undo: "取り消す"; case .redo: "やり直す"; case .replay: "音声を再生"; case .voice: "自分の声を録音・再生"; case .speech: "読み上げ音声を選択"; case .whiteboard: "手書きを切り替え"
        }
    }
}
struct ContentView: View {
    private struct BackgroundRequest: Hashable { let root: URL?; let settingsOpen: Bool }
    @StateObject private var model = StudyModel()
    @State private var deckBackgroundImage: UIImage?
    @State private var deckBackgroundRoot: URL?
    @State private var deckBackgroundError: String?
    @ObservedObject private var notificationRoute = ReviewNotificationRoute.shared
    @State private var importing = false
    #if DEBUG
    @State private var lastReviewSwipe = "none"
    #endif
    @State private var pendingTemplateAction: Int?
    @State private var templateActionKey: String?
    @State private var pendingPanelAction: ReviewerPanelAction?
    @State private var addingOcclusion = false
    @State private var customStudy: CustomStudyRequest?
    @State private var filteredDeck: FilteredDeckRequest?
    @State private var deckDescription: DeckDescriptionRequest?
    @State private var deckName = ""
    @State private var deckSearch = ""
    @State private var uploadConfirmation = ""
    @State private var namingDeck = false
    @State private var renamingDeck: Deck?
    @State private var deletingDeck: Deck?
    @State private var drawing = PKDrawing()
    @State private var whiteboardPreferences = WhiteboardPreferences()
    @State private var whiteboardToolPicker = true
    @State private var eraser = false
    @State private var tapSuppressedUntil = Date.distantPast
    @AppStorage("whiteboardPencilOnly") private var legacyPencilOnly = false
    @AppStorage("keepWhiteboard") private var keepWhiteboard = false
    @AppStorage("reviewGestureConfiguration") private var gestureConfigurationData = Data()
    @AppStorage("reviewKeyboardConfiguration") private var keyboardConfigurationData = Data()
    @AppStorage("reviewGamepadConfiguration") private var gamepadConfigurationData = Data()
    @AppStorage("reviewTouchConfiguration") private var touchConfigurationData = Data()
    @AppStorage("reviewToolbarConfiguration") private var toolbarConfigurationData = Data()
    @AppStorage("answerButtonPosition") private var answerButtonPosition = "bottom"
    @AppStorage("answerButtonSize") private var answerButtonSize = 100
    @AppStorage("showLargeAnswerButtons") private var largeAnswerButtons = false
    @AppStorage("showDeckTitle") private var showDeckTitle = false
    @AppStorage("showETA") private var showETA = false
    @AppStorage("showCardAnswerButtonTime") private var answerHoldMilliseconds = 0
    @AppStorage("dayTheme") private var dayTheme = "1"
    @AppStorage("nightTheme") private var nightTheme = "3"
    private var activeTheme: StudyTheme { StudyTheme.resolve(dark: colorScheme == .dark, day: dayTheme, night: nightTheme) }
    @ScaledMetric(relativeTo: .body) private var answerFontSize: CGFloat = 17
    @AppStorage("swipeReview") private var swipeReview = true
    @AppStorage("syncShowStatusBadge") private var showSyncStatusBadge = true
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var colorScheme
    private let ratings: [(String, Color)] = [("もう一度", .red), ("難しい", .orange), ("普通", .green), ("簡単", .blue)]
    var body: some View {
        NavigationStack { observedContent }
            .onChange(of: model.selected?.id, initial: true) { _, _ in loadWhiteboard() }
            .task(id: BackgroundRequest(root: model.profilesReady ? model.engine.root : nil, settingsOpen: model.showingSettings)) {
                guard model.profilesReady, !model.showingSettings else { return }
                let root = model.engine.root
                do {
                    let image = try await DeckBackgroundStore.shared.load(root: root)
                    guard !Task.isCancelled, model.engine.root == root else { return }
                    deckBackgroundImage = image; deckBackgroundRoot = root; deckBackgroundError = nil
                } catch {
                    guard !Task.isCancelled, model.engine.root == root else { return }
                    deckBackgroundImage = nil; deckBackgroundRoot = root
                    deckBackgroundError = "デッキ一覧の背景を読み込めませんでした: " + error.localizedDescription
                }
            }
            .background { reviewKeyboardCommands }
            .background { reviewGamepadCommands }
            .overlay(alignment: .bottomTrailing) {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--uitest-reminders") {
                    Text("通知予約の更新").font(.caption2).allowsHitTesting(false)
                        .accessibilityIdentifier("reminder-refresh-completions")
                        .accessibilityValue(String(model.reminderRefreshCompletions))
                }
                #endif
            }
            .overlay(alignment: .bottom) {
                if let toast = model.cardToast {
                    Text(toast).multilineTextAlignment(.center).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding()
                        .accessibilityIdentifier("card-script-toast").onTapGesture { model.cardToast = nil }
                }
            }
    }
    @ViewBuilder private var customReviewToolbar: some View {
        let configuration = ReviewToolbarConfiguration.load(toolbarConfigurationData)
        if configuration.enabled && model.reviewDisplayMode == .buttonsAndMenu && !configuration.items.isEmpty {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(configuration.items) { item in
                        Button(item.action.title) { performGesture(item.action) }
                            .buttonStyle(.bordered)
                            .disabled(item.action == .none || model.card == nil || model.busy || model.reviewingInteractionBlocked || !model.schedulerReady)
                            .accessibilityIdentifier("review-toolbar-" + item.id.uuidString)
                    }
                }.padding(.horizontal).padding(.vertical, 6)
            }.accessibilityIdentifier("custom-review-toolbar")
        }
    }
    private var reviewGamepadCommands: some View {
        let configuration = ReviewGamepadConfiguration.load(gamepadConfigurationData)
        return ReviewGamepadInput(enabled: configuration.enabled && model.card != nil && !model.busy
            && !model.reviewingInteractionBlocked && model.schedulerReady && phase == .active) { button in
            guard !model.busy, !model.reviewingInteractionBlocked, model.schedulerReady, phase == .active else { return }
            performGesture(configuration.action(for: button))
        }.frame(width: 0, height: 0).accessibilityHidden(true)
    }
    private var reviewKeyboardCommands: some View {
        let configuration = ReviewKeyboardConfiguration.load(keyboardConfigurationData)
        return VStack {
            ForEach(ReviewKey.allCases) { key in
                let action = configuration.action(for: key)
                Button(action.title) { performGesture(action) }
                    .keyboardShortcut(key.shortcut)
                    .disabled(action == .none || model.card == nil || model.busy || model.reviewingInteractionBlocked || !model.schedulerReady
                        || (!model.revealed && model.card?.typing != nil && key != .enter))
            }
        }.frame(width: 0, height: 0).clipped().opacity(0).accessibilityHidden(true)
    }
    private func openCardAction(_ action: ReviewCardAction) {
        guard let card = model.card else { return }
        model.cardActionRequest = ReviewCardActionRequest(cardID: card.id, noteID: card.noteID, action: action)
    }
    private var navigationContent: some View {
        VStack(spacing: 0) {
            if model.selected != nil { reviewer }
            else { deckList }
            if model.busy {
                HStack {
                    ProgressView(model.isSyncing ? model.syncStatus : "処理中…")
                    if model.isSyncing { Button("中止", action: model.cancelSync) }
                }.padding().accessibilityIdentifier("busy")
            }
        }
        .disabled(!model.profilesReady)
        .navigationTitle(model.selected.map { showDeckTitle ? $0.name : "" } ?? (model.profileRegistry.profiles.count > 1 ? "AnkiPad · " + model.currentProfile.name : "AnkiPad"))
        .toolbar { navigationToolbar }
        .toolbar(model.selected != nil && model.reviewDisplayMode.isFullscreen ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(model.selected != nil && model.reviewDisplayMode.isFullscreen)
        .simultaneousGesture(TapGesture(count: 3).onEnded { tapSuppressedUntil = Date().addingTimeInterval(0.8); model.reviewDisplayMode = .buttonsAndMenu }, including: model.selected != nil && model.reviewDisplayMode.isFullscreen ? .all : .subviews)
    }
    @ToolbarContentBuilder private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if model.selected != nil { Button("デッキ", action: model.leave).disabled(model.busy || !model.profilesReady) }
            else { Button { model.showingNavigationDrawer = true } label: { Image(systemName: "sidebar.left") }.accessibilityLabel("ナビゲーション").accessibilityIdentifier("navigation-menu") }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if model.selected != nil {
                Button(action: model.replay) { Image(systemName: "speaker.wave.2") }.accessibilityLabel("音声を再生").accessibilityIdentifier("review-replay-audio")
                Button { updateWhiteboard { $0.toggleEnabled() } } label: { Image(systemName: whiteboardPreferences.enabled ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle") }.accessibilityLabel("手書きボード").accessibilityIdentifier("whiteboard-toggle")
                if whiteboard { Button { drawing = PKDrawing() } label: { Image(systemName: "trash") }.accessibilityLabel("手書きを消す") }
                Button("取り消す", action: undoStrokeOrReview).disabled(model.busy || !model.profilesReady).accessibilityIdentifier("review-undo")
                Menu {
                    Button("やり直す") { model.redo() }
                    Button("自分の声を録音・再生", systemImage: "mic") {
                        model.openReviewVoice()
                    }.disabled(model.card == nil || model.busy)
                    Button("読み上げ音声を選択") { model.openSpeechVoicePicker() }.accessibilityIdentifier("review-speech-choice")
                    Button("ノートを追加") { model.editorRequest = EditorRequest(deckID: model.selected?.id ?? "0") }
                    if whiteboardPreferences.enabled {
                        Button(whiteboardPreferences.visible ? "手書きを隠す" : "手書きを表示") { updateWhiteboard { $0.toggleVisible() } }
                            .accessibilityIdentifier("whiteboard-visibility")
                    }
                    if whiteboard {
                        Button(whiteboardToolPicker ? "ペンの色・道具を隠す" : "ペンの色・道具を表示") { whiteboardToolPicker.toggle() }
                            .accessibilityIdentifier("whiteboard-pen-palette")
                        Toggle("消しゴム", isOn: $eraser)
                        Toggle("Apple Pencilのみで描く", isOn: Binding(get: { whiteboardPreferences.stylusOnly }, set: { value in updateWhiteboard { $0.stylusOnly = value } }))
                            .accessibilityIdentifier("whiteboard-stylus-only")
                        Button("手書きを画像で保存") {
                            let bounds = drawing.bounds
                            guard !bounds.isEmpty, !bounds.isNull else { return }
                            if let data = drawing.image(from: bounds.insetBy(dx: -12, dy: -12), scale: 2).pngData() {
                                do {
                                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("whiteboard-" + UUID().uuidString + ".png")
                                    try data.write(to: url)
                                    model.exportURL = url
                                } catch { model.error = error.localizedDescription }
                            }
                        }.disabled(drawing.strokes.isEmpty)
                    }
                    Button(model.card?.marked == true ? "マークを外す" : "マークを付ける", systemImage: model.card?.marked == true ? "star.fill" : "star") { model.toggleCurrentMark() }
                    Button("ノートを編集") { if let card = model.card { model.editorRequest = EditorRequest(cardID: card.id, deckID: card.deckID) } }.accessibilityIdentifier("review-edit-note")
                    Toggle("自動進行", isOn: $model.autoAdvance).accessibilityIdentifier("auto-advance-toggle").onChange(of: model.autoAdvance) { _, _ in model.scheduleAutoAdvance() }
                    Button("ユーザー操作") {
                        templateActionKey = model.card?.mutationKey
                        model.showingTemplateActions = true
                    }.accessibilityIdentifier("template-actions-menu")
                    Button("次のヒントを表示") { model.showTemplateHint(all: false) }.accessibilityIdentifier("template-hint-next")
                    Button("すべてのヒントを表示") { model.showTemplateHint(all: true) }
                    Button("タグを編集") { openCardAction(.tags) }
                    Button("期日を変更") { openCardAction(.due) }
                    Button("新規カードに戻す") { openCardAction(.reset) }
                    Button("カード情報") { if let card = model.card { model.backendPage = BackendPageRequest(path: "card-info/" + card.id, title: "カード情報") } }
                    Button("保留") { model.modifyCurrent { try await model.engine.suspend([$0.id]) } }
                    Button("今日は表示しない") { model.modifyCurrent { try await model.engine.bury([$0.id]) } }
                    Button("関連カードを今日は表示しない") { model.modifyCurrent { try await model.engine.bury([$0.noteID], note: true) } }
                    Menu("フラグ") {
                        ForEach(0..<8, id: \.self) { flag in Button(flag == 0 ? "なし" : "フラグ \(flag)") { model.setCurrentFlag(flag) } }
                    }
                } label: { Image(systemName: "ellipsis.circle") }.disabled(model.busy || model.card == nil).accessibilityIdentifier("reviewer-menu")
            } else {
                Button(action: { model.synchronize() }) { Image(systemName: "arrow.triangle.2.circlepath") }
                    .accessibilityLabel("AnkiWebと同期").accessibilityIdentifier("sync")
                    .disabled(model.busy || !model.profilesReady)
                Button { model.showingAccount = true } label: { Image(systemName: "person.crop.circle") }
                    .accessibilityLabel("AnkiWebアカウント").accessibilityIdentifier("ankiweb-account")
                    .disabled(model.busy || !model.profilesReady)
                Button { model.editorRequest = EditorRequest() } label: { Image(systemName: "plus") }.accessibilityLabel("ノートを追加").accessibilityIdentifier("add-note").disabled(model.busy || !model.profilesReady)
                Menu {
                    Button("カードブラウザー", systemImage: "rectangle.stack") { model.browserSearch = ""; model.showingBrowser = true }.accessibilityIdentifier("browser-open")
                    Button("プロファイル", systemImage: "person.2") { model.showingProfiles = true }.accessibilityIdentifier("profiles-open")
                    Button("共有デッキを取得", systemImage: "arrow.down.circle") { model.showingSharedDecks = true }.accessibilityIdentifier("shared-decks")
                    Button("統計", systemImage: "chart.bar") { model.backendPage = BackendPageRequest(path: "graphs", title: "統計") }.accessibilityIdentifier("statistics")
                    Button("フィルターデッキを作成") { filteredDeck = FilteredDeckRequest() }
                    Button("画像穴埋めを追加", systemImage: "rectangle.dashed") { addingOcclusion = true }.accessibilityIdentifier("add-occlusion")
                    Button("ノートタイプ", systemImage: "rectangle.stack.badge.gearshape") { model.showingNoteTypes = true }.accessibilityIdentifier("notetypes")
                    Button("設定", systemImage: "gearshape") { model.showingSettings = true }
                    Button("バックアップとチェック", systemImage: "externaldrive") { model.showingMaintenance = true }
                    Button("デッキを作成", systemImage: "folder.badge.plus") { renamingDeck = nil; deckName = ""; namingDeck = true }
                    Button("デッキを取り込む", systemImage: "square.and.arrow.down") { importing = true }
                    Button("すべて書き出す", systemImage: "square.and.arrow.up", action: model.exportFile)
                    Button("コレクションをすべて書き出す", systemImage: "externaldrive.badge.plus", action: model.exportCollectionFile)
                    Button("更新", systemImage: "arrow.clockwise", action: model.refresh)
                } label: { Image(systemName: "ellipsis.circle") }.disabled(model.busy || !model.profilesReady).accessibilityIdentifier("collection-menu")
            }
        }
    }
    private var reviewerOptionsPanel: some View {
        NavigationStack {
            List {
                ForEach(ReviewerPanelAction.allCases) { action in
                    Button(action.title) { pendingPanelAction = action; model.showingReviewerOptions = false }
                        .disabled(model.busy || !model.profilesReady).accessibilityIdentifier("review-option-" + action.rawValue)
                }
            }
            .accessibilityIdentifier("reviewer-options-list")
            .studyThemeSurface().navigationTitle("カードの操作")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { model.showingReviewerOptions = false } } }
        }
    }
    private func finishReviewerPanelAction() {
        guard let action = pendingPanelAction else { return }
        pendingPanelAction = nil
        guard !model.busy else { return }
        switch action {
        case .edit: if let card = model.card { model.editorRequest = EditorRequest(cardID: card.id, deckID: card.deckID) }
        case .add: model.editorRequest = EditorRequest(deckID: model.selected?.id ?? "0")
        case .tags: openCardAction(.tags)
        case .due: openCardAction(.due)
        case .reset: openCardAction(.reset)
        case .info: if let card = model.card { model.backendPage = BackendPageRequest(path: "card-info/" + card.id, title: "カード情報") }
        case .mark: model.toggleCurrentMark()
        case .suspend: model.modifyCurrent { try await model.engine.suspend([$0.id]) }
        case .suspendNote: model.modifyCurrent { _ = try await model.engine.call("SchedulerService.BuryOrSuspendCards", ["noteIds": [$0.noteID], "mode": "SUSPEND"]) }
        case .bury: model.modifyCurrent { try await model.engine.bury([$0.id]) }
        case .buryNote: model.modifyCurrent { try await model.engine.bury([$0.noteID], note: true) }
        case .undo: undoStrokeOrReview()
        case .redo: model.redo()
        case .replay: model.replay()
        case .voice: model.openReviewVoice()
        case .speech: model.openSpeechVoicePicker()
        case .whiteboard: updateWhiteboard { $0.toggleEnabled() }
        }
    }
    private var templateActionPicker: some View {
        NavigationStack {
            List(1...9, id: \.self) { number in
                Button("ユーザー操作 \(number)") {
                    pendingTemplateAction = number
                    model.showingTemplateActions = false
                }.accessibilityIdentifier("template-action-\(number)")
            }
            .studyThemeSurface().navigationTitle("ユーザー操作")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { model.showingTemplateActions = false } } }
        }
    }
    private func finishTemplateAction() {
        defer { pendingTemplateAction = nil; templateActionKey = nil }
        guard let number = pendingTemplateAction, model.card?.mutationKey == templateActionKey else { return }
        model.performTemplateAction(number)
    }
    private var sheetContent: some View {
        navigationContent
        .sheet(isPresented: $model.showingNavigationDrawer, onDismiss: model.finishNavigationSelection) { AppNavigationDrawerView(model: model) }
        .sheet(isPresented: $model.showingReviewVoice, onDismiss: {
            model.stopCardAudioForRecognition(); model.reviewVoice.finish()
        }) { ReviewVoiceView(model: model, recorder: model.reviewVoice) }
        .sheet(item: model.speechRequestBinding(inVoice: false), onDismiss: model.finishSpeechChoice) { request in
            ReviewSpeechVoiceView(model: model, request: request)
        }
        .sheet(isPresented: $model.showingTemplateActions, onDismiss: finishTemplateAction) { templateActionPicker }
        .sheet(isPresented: $model.showingReviewerOptions, onDismiss: finishReviewerPanelAction) { reviewerOptionsPanel }
        .sheet(isPresented: $model.showingNoteTypes) { NoteTypeManagerView(model: model) }
        .sheet(isPresented: $model.showingSettings) { SettingsView(model: model) }
        .sheet(isPresented: $model.showingMaintenance) { MaintenanceView(model: model) }
        .sheet(item: $model.backendPage) { BackendPageView(model: model, request: $0) }
        .sheet(item: $model.editorRequest) { NoteEditorView(model: model, request: $0) }
        .sheet(isPresented: $model.showingProfiles) { ProfileManagerView(model: model) }
        .sheet(isPresented: $model.showingSharedDecks) { SharedDeckBrowserView(model: model) }
        .sheet(isPresented: $model.showingBrowser) { BrowserView(model: model) }
        .sheet(item: $model.cardActionRequest) { ReviewCardActionsView(model: model, request: $0) }
        .sheet(item: $deckDescription) { DeckDescriptionView(model: model, request: $0) }
        .sheet(item: $customStudy) { CustomStudyView(model: model, request: $0) }
        .sheet(item: $filteredDeck) { FilteredDeckView(model: model, request: $0) }
        .sheet(isPresented: $addingOcclusion) { ImageOcclusionEntryView(model: model) }
        .sheet(isPresented: $model.showingAccount) { AccountView(model: model) }
    }
    private var deckDialogContent: some View {
        sheetContent
        .alert(renamingDeck == nil ? "デッキを作成" : "デッキ名を変更", isPresented: $namingDeck) {
            TextField("デッキ名", text: $deckName)
            Button("保存") {
                if let deck = renamingDeck { model.renameDeck(deck, name: deckName) }
                else { model.createDeck(deckName) }
            }.disabled(deckName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("キャンセル", role: .cancel) {}
        }
        .confirmationDialog("デッキとカードを削除しますか？", isPresented: Binding(get: { deletingDeck != nil }, set: { if !$0 { deletingDeck = nil } }), presenting: deletingDeck) { deck in
            Button("削除", role: .destructive) { model.deleteDeck(deck); deletingDeck = nil }
                .accessibilityIdentifier("deck-delete-confirm")
        } message: { _ in Text("子デッキと関連するカードも削除します。バックアップを保存してから削除します。") }
    }
    private var syncDialogContent: some View {
        deckDialogContent
        .alert("従量課金の回線です", isPresented: $model.meteredSyncPrompt) {
            Button("続ける") { model.synchronize(allowMeteredThisTime: true) }.accessibilityIdentifier("metered-sync-continue")
            Button("今後は確認しない") { model.allowMeteredSyncAlways() }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("モバイル回線などで同期すると、データ通信量がかかる場合があります。") }
        .confirmationDialog("同期するデータを選択", isPresented: Binding(get: { model.chooseFullSync && !model.busy && phase == .active }, set: { model.chooseFullSync = $0 }), titleVisibility: .visible) {
            if let decision = model.syncDecision {
                if decision.canDownload { Button("AnkiWebのデータをこのiPadにダウンロード", role: .destructive) { model.confirmDirection = false } }
                if decision.canUpload { Button("このiPadのデータをAnkiWebにアップロード", role: .destructive) { uploadConfirmation = ""; model.confirmDirection = true } }
                Button("キャンセル", role: .cancel) { model.syncDecision = nil }
            }
        } message: { Text((model.syncDecision?.localSummary ?? "") + "\n一方のコレクション全体を使う必要があります。置き換える側だけの変更は失われます。") }
        .alert("データを置き換えますか？", isPresented: Binding(get: { model.confirmDirection != nil }, set: { if !$0 { model.confirmDirection = nil } })) {
            if let upload = model.confirmDirection {
                if upload { TextField("アップロード と入力", text: $uploadConfirmation) }
                Button("置き換えて同期", role: .destructive) {
                    model.fullSync(upload: upload)
                    model.confirmDirection = nil
                    uploadConfirmation = ""
                }.disabled(upload && uploadConfirmation != "アップロード")
            }
            Button("キャンセル", role: .cancel) { uploadConfirmation = ""; model.confirmDirection = nil; model.syncDecision = nil }
        } message: { Text((model.syncDecision?.localSummary ?? "") + "\n" + (model.confirmDirection == true ? "AnkiWebのコレクション全体を、このiPadのデータで置き換えます。AnkiWebだけにある変更は失われます。続ける場合は「アップロード」と入力してください。" : "このiPadのコレクションをAnkiWebのデータで置き換えます。取り込み前のローカルバックアップを保存します。")) }
    }
    private var importExportContent: some View {
        syncDialogContent
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "apkg") ?? .data, UTType(filenameExtension: "colpkg") ?? .data, .commaSeparatedText, .tabSeparatedText, .plainText]) { result in
            switch result {
            case .success(let url):
                if url.pathExtension.lowercased() == "colpkg" { model.pendingCollectionImport = url }
                else { model.importFile(url) }
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .confirmationDialog("コレクションを置き換えますか？", isPresented: Binding(get: { model.pendingCollectionImport != nil }, set: { if !$0 { model.pendingCollectionImport = nil } })) {
            if let url = model.pendingCollectionImport { Button("バックアップして置き換える", role: .destructive) { model.importFile(url); model.pendingCollectionImport = nil } }
        } message: { Text("現在のコレクションを読み込むファイルで置き換えます。現在のデータはバックアップに保存します。") }
        .sheet(isPresented: Binding(get: { model.exportURL != nil }, set: { if !$0 { model.exportURL = nil } })) {
            if let url = model.exportURL { ShareSheet(url: url) }
        }
    }
    private var errorContent: some View {
        importExportContent
        .alert("処理できませんでした", isPresented: Binding(get: { model.error != nil && !model.showingAccount }, set: { if !$0 { model.error = nil } })) {
            Button("閉じる", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private func openPendingReminder() {
        guard model.profilesReady, !model.busy, phase == .active,
              !model.reviewingInteractionBlocked, let id = notificationRoute.take() else { return }
        guard model.profileRegistry.profiles.contains(where: { $0.id == id }) else {
            model.error = "通知のプロファイルが見つかりません。削除済みの可能性があります。"
            return
        }
        Task {
            do {
                try await model.switchProfile(id)
                if model.selected != nil { model.leave() }
            } catch { model.error = error.localizedDescription }
        }
    }
    private var observedContent: some View {
        errorContent
        .task { model.bootstrap(); openPendingReminder(); model.requestAutomaticSync(.foreground) }
        .onChange(of: model.currentProfileID) { _, _ in model.requestAutomaticSync(.foreground) }
        .onChange(of: localCollectionPresentationActive) { _, active in
            model.collectionPresentationActive = active
            if !active { model.processPendingAutomaticSync() }
        }
        .onChange(of: notificationRoute.profileID) { _, _ in openPendingReminder() }
        .onChange(of: model.profilesReady) { _, _ in openPendingReminder() }
        .onChange(of: model.busy) { _, busy in if !busy { openPendingReminder() } }
        .onChange(of: phase) { _, value in
            if value == .inactive { model.pauseReviewScene() }
            if value == .background { model.replayStop(); model.requestAutomaticSync(.background) }
            if value == .active { model.resumeReviewScene(); openPendingReminder(); model.requestAutomaticSync(.foreground) }
        }
        .onChange(of: model.reviewingInteractionBlocked) { _, blocked in
            if blocked { model.pauseReviewInteraction() } else { model.resumeReviewInteraction(); model.scheduleConditionalReminderRefresh(); openPendingReminder(); model.processPendingAutomaticSync() }
        }
        .alert("学習の区切り", isPresented: Binding(get: { model.timeboxReport != nil && !model.busy && phase == .active }, set: { if !$0 { model.timeboxReport = nil } })) {
            Button("続ける") { model.timeboxReport = nil }.accessibilityIdentifier("timebox-continue")
            Button("学習を終了") { model.leave() }.accessibilityIdentifier("timebox-finish")
        } message: { Text(model.timeboxReport?.message ?? "") }
        .alert("自動進行", isPresented: $model.timedReminder) { Button("閉じる", role: .cancel) {} } message: { Text("カードの表示時間が終了しました。解答または評価を選んでください。") }
    }
    private var localCollectionPresentationActive: Bool {
        importing || addingOcclusion || customStudy != nil || filteredDeck != nil || deckDescription != nil
            || namingDeck || deletingDeck != nil || model.pendingCollectionImport != nil
    }
    private var deckList: some View {
        themedDeckList.scrollContentBackground(.hidden).background {
            GeometryReader { geometry in
                if let image = currentDeckBackground {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        .allowsHitTesting(false).accessibilityHidden(true)
                } else { Color(uiColor: activeTheme.nativeBackground) }
            }
        }
    }
    private var currentDeckBackground: UIImage? { model.profilesReady && deckBackgroundRoot == model.engine.root ? deckBackgroundImage : nil }
    private var deckRowBackground: Color? { currentDeckBackground == nil ? nil : .clear }
    private var themedDeckList: some View {
        List {
            if let error = deckBackgroundError, deckBackgroundRoot == model.engine.root {
                Text(error).foregroundStyle(.secondary).listRowBackground(deckRowBackground)
            }
            if let warning = model.reminderUpdateError { Text(warning).foregroundStyle(.secondary) }
            Section {
                ForEach(Deck.visible(model.decks, search: deckSearch)) { deck in
                    HStack(spacing: 0) {
                        if deck.hasChildren {
                            Button { model.toggleDeckCollapsed(deck) } label: {
                                Image(systemName: deck.collapsed ? "chevron.right" : "chevron.down")
                                    .frame(width: 36, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(deck.name + (deck.collapsed ? "を展開" : "を折りたたむ"))
                            .accessibilityValue(deck.collapsed ? "折りたたみ" : "展開")
                            .accessibilityIdentifier("deck-collapse-\(deck.id)")
                            .disabled(model.busy || !model.profilesReady)
                        } else { Color.clear.frame(width: 36, height: 1).accessibilityHidden(true) }
                        Button { model.select(deck) } label: {
                            HStack {
                                Text(deck.name).foregroundStyle(.primary)
                                Spacer()
                                Text("\(deck.newCount)").foregroundStyle(activeTheme == .eink ? Color.primary : .blue).monospacedDigit()
                                Text("\(deck.learnCount)").foregroundStyle(activeTheme == .eink ? Color.primary : .orange).monospacedDigit()
                                Text("\(deck.reviewCount)").foregroundStyle(activeTheme == .eink ? Color.primary : .green).monospacedDigit()
                            }.padding(.vertical, 8).frame(maxWidth: .infinity).contentShape(Rectangle())
                        }.buttonStyle(.borderless).disabled(model.busy || !model.profilesReady).accessibilityIdentifier("deck-\(deck.id)")
                        .accessibilityAddTraits(deck.isSelected ? .isSelected : [])
                        .contextMenu {
                            Button("デッキの説明") { deckDescription = DeckDescriptionRequest(deck: deck) }
                            if deck.filtered {
                                Button("フィルターデッキを編集") { filteredDeck = FilteredDeckRequest(deckID: deck.id) }
                                Button("フィルターデッキを再構築") { model.run { _ = try await model.engine.call("SchedulerService.RebuildFilteredDeck", ["did": deck.id]); model.refreshAfterEditing() } }
                                Button("フィルターデッキを空にする") { model.run { _ = try await model.engine.call("SchedulerService.EmptyFilteredDeck", ["did": deck.id]); model.refreshAfterEditing() } }
                            } else {
                                Button("カスタム学習") { customStudy = CustomStudyRequest(deck: deck) }
                            }
                            Button("デッキオプション") { model.backendPage = BackendPageRequest(path: "deck-options/" + deck.id, title: "デッキオプション") }
                            Button("統計") { model.run { try await model.engine.select(deck.id); model.backendPage = BackendPageRequest(path: "graphs", title: "統計") } }
                            Button("名前を変更") { renamingDeck = deck; deckName = deck.name; namingDeck = true }
                            Button("ノートを追加") { model.editorRequest = EditorRequest(deckID: deck.id) }.accessibilityIdentifier("deck-add-note-\(deck.id)")
                            Button("削除", role: .destructive) { deletingDeck = deck }
                        }
                    }.padding(.leading, CGFloat(deck.level) * 16)
                        .listRowBackground(deck.isSelected
                            ? activeTheme.selectedDeckBackground.opacity(currentDeckBackground == nil ? 1 : 114.0 / 255)
                            : deckRowBackground)
                }
            } header: { Text("デッキ                         新規 · 学習 · 復習") }
            .listRowBackground(deckRowBackground)
            Section {
                if let account = model.account {
                    Text(account.username).font(.subheadline)
                    if let date = model.lastSync { Text("最終同期: \(date.formatted())").font(.caption).foregroundStyle(.secondary) }
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--uitest-sync-timing"), let date = model.lastSync {
                        Text(String(date.timeIntervalSince1970)).accessibilityIdentifier("sync-completed-at")
                    }
                    if ProcessInfo.processInfo.arguments.contains("--uitest-sync-timing"), let date = model.debugBackgroundSyncCompletedAt {
                        Text(String(date.timeIntervalSince1970)).accessibilityIdentifier("background-sync-completed-at")
                    }
                    #endif
                } else {
                    Button("AnkiWebにログイン") { model.showingAccount = true }.accessibilityIdentifier("login-entry")
                }
                if !model.syncStatus.isEmpty { Text(model.syncStatus).font(.caption).foregroundStyle(.secondary) }
                if model.syncDecision != nil {
                    Text("同期方向の確認が必要です").accessibilityIdentifier("sync-direction-pending")
                } else if model.localSyncState?.hasChanges == true {
                    if showSyncStatusBadge {
                        Label("未同期の変更があります", systemImage: "arrow.triangle.2.circlepath").accessibilityIdentifier("sync-local-changes")
                    }
                } else if model.mediaSyncPending {
                    Text("同期が完了していません").font(.caption).accessibilityIdentifier("sync-media-pending")
                } else if model.localSyncState?.neverSynced == true {
                    Text("まだ同期していません").font(.caption)
                } else if model.localSyncState == nil && !model.busy {
                    Text("ローカルの同期状態を確認できませんでした").font(.caption)
                }
                Button(".apkgファイルを取り込む", systemImage: "square.and.arrow.down") { importing = true }.disabled(model.busy || !model.profilesReady)
                Text("AnkiDroidまたはAnkiから書き出したデッキを読み込めます。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.listRowBackground(deckRowBackground)
        }
        .searchable(text: $deckSearch, prompt: "デッキを検索")
    }
    private var effectiveAnswerPosition: AnswerButtonPosition {
        model.reviewDisplayMode == .allGone ? .none : (AnswerButtonPosition(rawValue: answerButtonPosition) ?? .bottom)
    }
    private var answerScale: CGFloat { CGFloat(min(200, max(10, answerButtonSize))) / 100 }
    private func ratingButton(_ rating: Int, card: StudyCard) -> some View {
        Button { model.answerFromButton(rating, cardKey: card.mutationKey) } label: {
            VStack(spacing: 6 * answerScale) {
                if card.options.showIntervals && card.intervals.indices.contains(rating) {
                    Text(card.intervals[rating]).font(.system(size: answerFontSize * 0.75 * answerScale))
                }
                Text(ratings[rating].0).fontWeight(.semibold)
            }.font(.system(size: answerFontSize * answerScale))
                .frame(maxWidth: .infinity, minHeight: max(44, 44 * answerScale))
                .padding(.vertical, 6 * answerScale).contentShape(Rectangle())
        }
        .buttonStyle(.bordered).tint(activeTheme.isMonochrome ? activeTheme.accent : ratings[rating].1)
        .disabled(model.busy || model.reviewingInteractionBlocked || !model.schedulerReady)
        .accessibilityIdentifier("answer-\(rating)")
    }
    @ViewBuilder private func answerControls(_ card: StudyCard) -> some View {
        Divider()
        if model.revealed {
            VStack(spacing: 8) {
                // Upstream's large layout: Hard/Easy, then Again/Good.
                ForEach(0..<(largeAnswerButtons ? 2 : 1), id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(largeAnswerButtons ? (row == 0 ? [1, 3] : [0, 2]) : [0, 1, 2, 3], id: \.self) { rating in
                            ratingButton(rating, card: card)
                        }
                    }
                }
            }.padding()
        } else {
            ReviewRevealButton(milliseconds: answerHoldMilliseconds,
                               enabled: !model.busy && !model.reviewingInteractionBlocked && model.schedulerReady,
                               cardKey: card.mutationKey, action: { model.revealFromButton(cardKey: card.mutationKey) }) {
                VStack {
                    Text("解答を表示").font(.system(size: answerFontSize * answerScale))
                    if answerHoldMilliseconds > 0 { Text("\(answerHoldMilliseconds)ミリ秒長押し").font(.caption) }
                }.frame(minHeight: max(44, 44 * answerScale))
            }.buttonStyle(.borderedProminent).controlSize(.large).padding()
                .disabled(model.busy || model.reviewingInteractionBlocked || !model.schedulerReady)
                .accessibilityIdentifier("reveal")
        }
    }
    @ViewBuilder private var reviewer: some View {
        if let card = model.card {
            if showETA && !model.reviewDisplayMode.isFullscreen {
                ReviewETAView(engine: model.engine, cardKey: card.mutationKey)
            }
            if model.showReviewTopbar && model.reviewDisplayMode != .allGone {
            HStack {
                if card.options.showCounts { Text(card.counts) }
                if card.options.showTimer {
                    TimelineView(.periodic(from: Date(), by: 1)) { _ in
                        let elapsed = max(0, Int(model.elapsed()))
                        let seconds = card.options.capMilliseconds > 0 ? min(card.options.capMilliseconds / 1000, elapsed) : elapsed
                        Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                    }
                }
            }.font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).padding(12)
            }
            customReviewToolbar
            if effectiveAnswerPosition == .top { answerControls(card) }
            ZStack {
                ReviewerWebView(html: model.revealed ? (model.answerOverride ?? card.answer) : card.question, css: card.css,
                cardID: card.id, ordinal: card.ordinal, typing: card.typing, hideAudioButtons: card.options.hideAudioButtons, typedAnswer: $model.typedAnswer,
                answer: model.revealed, media: model.engine.media,
                playTag: { model.playTag(answer: $0, index: $1) }, reveal: model.reveal,
                scheduling: card, schedulingRequest: { try await model.schedulingRequest($0, input: $1, key: card.mutationKey) },
                schedulingError: { model.schedulingFailed($0, key: card.mutationKey) },
                cardAPI: { try await model.ankiDroidCardAPI($0, request: $1, cardID: card.id, mutationKey: card.mutationKey) },
                cardScriptEvents: model.cardScriptEvents,
                scriptEventDelivered: { id in model.cardScriptEvents.removeAll { $0.id == id } },
                scriptEventError: { model.cardToast = $0 },
                scriptDialogChanged: { model.cardDialogPresented = $0 },
                swipeHandler: { x, y in
                    let action = ReviewGestureConfiguration.load(gestureConfigurationData).action(x: x, y: y)
                    #if DEBUG
                    lastReviewSwipe = "\(Int(x)),\(Int(y)) action=\(action.rawValue) readyAtInput=\(model.schedulerReady) busyAtInput=\(model.busy) blockedAtInput=\(model.reviewingInteractionBlocked)"
                    #endif
                    guard swipeReview, !whiteboard, !model.busy, !model.reviewingInteractionBlocked else { return }
                    performGesture(action)
                }, tapHandler: { x, y in
                    guard !whiteboard, !model.busy, !model.reviewingInteractionBlocked, model.schedulerReady,
                          model.card?.mutationKey == card.mutationKey, Date() >= tapSuppressedUntil else { return }
                    performGesture(ReviewTouchConfiguration.load(touchConfigurationData).action(x: x, y: y, revealed: model.revealed))
                })
                if whiteboard {
                    WhiteboardCanvas(drawing: $drawing, pencilOnly: whiteboardPreferences.stylusOnly, eraser: eraser,
                                     penColor: whiteboardPreferences.penColor(dark: colorScheme == .dark).map(UIColor.init(whiteboardRGBA:)),
                                     toolPickerVisible: whiteboardToolPicker,
                                     penColorChanged: { color in
                                         let dark = colorScheme == .dark
                                         guard whiteboardPreferences.penColor(dark: dark) != color.whiteboardRGBA else { return }
                                         updateWhiteboard { $0.setPenColor(color.whiteboardRGBA, dark: dark) }
                                     })
                }
            }
            .overlay(alignment: .topLeading) {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--uitest-fixture") {
                    Text("swipe enabled=\(swipeReview) busy=\(model.busy) blocked=\(model.reviewingInteractionBlocked) ready=\(model.schedulerReady) pan=\(lastReviewSwipe)")
                        .font(.caption2).foregroundStyle(.secondary).allowsHitTesting(false)
                        .accessibilityIdentifier("review-swipe-diagnostics")
                }
                #endif
            }
            .onChange(of: card.id) { _, _ in
                if !keepWhiteboard { drawing = PKDrawing() }
            }
            if effectiveAnswerPosition == .bottom { answerControls(card) }
        } else if model.finished {
            ContentUnavailableView("このデッキの学習は終了です", systemImage: "checkmark.circle", description: Text("デッキ一覧に戻って、別のデッキを選べます。"))
        } else { Spacer() }
    }
}


private extension ContentView {
    private var whiteboard: Bool { whiteboardPreferences.showsCanvas }
    private var whiteboardKey: String? {
        model.selected.map { model.profilePreferenceKey(WhiteboardPreferences.key(deckID: $0.id)) }
    }
    private func loadWhiteboard() {
        whiteboardPreferences = WhiteboardPreferences.load(whiteboardKey.flatMap { UserDefaults.standard.data(forKey: $0) }, legacyStylusOnly: legacyPencilOnly)
        whiteboardToolPicker = true
        eraser = false
    }
    private func updateWhiteboard(_ change: (inout WhiteboardPreferences) -> Void) {
        change(&whiteboardPreferences)
        if !whiteboard { eraser = false }
        if let key = whiteboardKey { UserDefaults.standard.set(whiteboardPreferences.encoded(), forKey: key) }
    }
    /// Upstream undoes the last whiteboard stroke before undoing a review while the whiteboard is shown.
    private func undoStrokeOrReview() {
        if whiteboard, !drawing.strokes.isEmpty { drawing.strokes.removeLast() } else { model.undo() }
    }
    func performGesture(_ action: ReviewGestureAction) {
        switch action {
        case .none: break
        case .flipOrGood, .flipOrAgain:
            if model.revealed { model.answer(action == .flipOrGood ? 2 : 0) } else { model.reveal() }
        case .showAnswer: model.reveal()
        case .again: model.answer(0)
        case .hard: model.answer(1)
        case .good: model.answer(2)
        case .easy: model.answer(3)
        case .replay: model.replay()
        case .recordVoice: model.recordReviewVoice()
        case .replayVoice: model.replayReviewVoice()
        case .saveVoice: model.saveReviewRecording()
        case .selectTTS: model.openSpeechVoicePicker()
        case .undo: undoStrokeOrReview()
        case .redo: model.redo()
        case .mark: model.toggleCurrentMark()
        case .edit: if let card = model.card { model.editorRequest = EditorRequest(cardID: card.id, deckID: card.deckID) }
        case .add: model.editorRequest = EditorRequest(deckID: model.selected?.id ?? "0")
        case .tags: openCardAction(.tags)
        case .bury: model.modifyCurrent { try await model.engine.bury([$0.id]) }
        case .suspend: model.modifyCurrent { try await model.engine.suspend([$0.id]) }
        case .whiteboard: updateWhiteboard { $0.toggleEnabled() }
        case .eraser: if whiteboard { eraser.toggle() }
        case .clearWhiteboard: drawing = PKDrawing()
        case .penColor: if whiteboard { whiteboardToolPicker.toggle() }
        case .autoAdvance: model.autoAdvance.toggle(); model.scheduleAutoAdvance()
        case .hint: model.showTemplateHint(all: false)
        case .allHints: model.showTemplateHint(all: true)
        default:
            if action.rawValue.hasPrefix("flag"), let flag = Int(action.rawValue.dropFirst(4)) {
                model.setCurrentFlag(model.card?.flag == flag ? 0 : flag)
            } else if action.rawValue.hasPrefix("user"), let number = Int(action.rawValue.dropFirst(4)) {
                model.performTemplateAction(number)
            }
        }
    }
}
