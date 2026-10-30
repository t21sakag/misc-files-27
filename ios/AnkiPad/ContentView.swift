import SwiftUI
import UniformTypeIdentifiers
import PencilKit
import UIKit

private enum ReviewerPanelAction: String, CaseIterable, Identifiable {
    case edit, add, tags, due, reset, info, mark, suspend, suspendNote, bury, buryNote, undo, redo, replay, voice, speech, whiteboard
    var id: String { rawValue }
    var title: String {
        switch self {
        case .edit: AppText.localized("ノートを編集"); case .add: AppText.localized("ノートを追加"); case .tags: AppText.localized("タグを編集")
        case .due: AppText.localized("期日を変更"); case .reset: AppText.localized("新規カードに戻す"); case .info: AppText.localized("カード情報")
        case .mark: AppText.localized("マークを切り替え"); case .suspend: AppText.localized("カードを保留"); case .suspendNote: AppText.localized("関連カードを保留")
        case .bury: AppText.localized("カードを今日は表示しない"); case .buryNote: AppText.localized("関連カードを今日は表示しない")
        case .undo: AppText.localized("取り消す"); case .redo: AppText.localized("やり直す"); case .replay: AppText.localized("音声を再生"); case .voice: AppText.localized("自分の声を録音・再生"); case .speech: AppText.localized("読み上げ音声を選択"); case .whiteboard: AppText.localized("手書きを切り替え")
        }
    }
}
struct ContentView: View {
    private struct BackgroundRequest: Hashable { let root: URL?; let settingsOpen: Bool }
    @StateObject private var model = StudyModel()
    @StateObject private var sharedInbox = SharedInboxController()
    @State private var showingSharedInbox = false
    @State private var activeSharedEditorReceipt: SharedInboxReceipt?
    @State private var deckBackgroundImage: UIImage?
    @State private var deckBackgroundRoot: URL?
    @State private var deckBackgroundError: String?
    @ObservedObject private var notificationRoute = ReviewNotificationRoute.shared
    @State private var browserLinks = BrowserLinkInbox()
    @State private var pendingWidgetRoute: WidgetRoute?
    @State private var browserLinkSearch: String?
    @State private var browserSessionActive = false
    @State private var openingReminder = false
    private struct ReceivedRequest: Identifiable {
        var id: UUID { file.id }
        let file: IncomingImportFile
        var receipt: SharedInboxReceipt?
        var draft: IncomingNoteDraft?
    }
    @State private var incomingFiles: [ReceivedRequest] = []
    @State private var incomingFileReview: ReceivedRequest?
    @State private var activeIncomingReceipt: SharedInboxReceipt?
    @State private var incomingFileCopies = 0
    private enum PendingNoteAction { case edit(EditorRequest), occlusion(ReceivedRequest) }
    @State private var pendingNoteActions: [PendingNoteAction] = []
    @State private var receivedOcclusionFile: ReceivedRequest?
    @State private var addingTextNote = false
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
    private let ratings: [(String, Color)] = [(AppText.localized("もう一度"), .red), (AppText.localized("難しい"), .orange), (AppText.localized("普通"), .green), (AppText.localized("簡単"), .blue)]
    var body: some View {
        NavigationStack { observedContent }
            .safeAreaInset(edge: .bottom) {
                if !incomingFiles.isEmpty || !pendingNoteActions.isEmpty || browserLinks.pending != nil {
                    Button(AppText.localized("受け取りを開く"), action: openPendingExternalRequest)
                        .disabled(!canPresentExternalRequest).padding(8)
                        .accessibilityIdentifier("received-open")
                } else if incomingFileCopies > 0 {
                    ProgressView(AppText.localized("ファイルを受信しています…")).padding(8)
                } else if !sharedInbox.entries.isEmpty || !sharedInbox.invalid.isEmpty {
                    Button(AppText.localized("共有の受信トレイ")) { showingSharedInbox = true }
                        .disabled(!canPresentExternalRequest).padding(8).accessibilityIdentifier("shared-inbox-open")
                }
            }
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
                    deckBackgroundError = AppText.localized("デッキ一覧の背景を読み込めませんでした: ") + error.localizedDescription
                }
            }
            .background { reviewKeyboardCommands }
            .background { reviewGamepadCommands }
            .overlay(alignment: .bottomTrailing) {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--uitest-reminders") {
                    Text(AppText.localized("通知予約の更新")).font(.caption2).allowsHitTesting(false)
                        .accessibilityIdentifier("reminder-refresh-completions")
                        .accessibilityValue(String(model.reminderRefreshCompletions))
                }
                if UITestIsolation.namespace() != nil, ProcessInfo.processInfo.arguments.contains("--uitest-widgets") {
                    Text("Widget snapshot observation").font(.caption2).allowsHitTesting(false)
                        .accessibilityIdentifier("widget-snapshot-state")
                        .accessibilityValue(model.widgetSnapshotInspection)
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
                    ProgressView(model.isSyncing ? model.syncStatus : AppText.localized("処理中…"))
                    if model.isSyncing { Button(AppText.localized("中止"), action: model.cancelSync) }
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
            if model.selected != nil { Button(AppText.localized("デッキ"), action: model.leave).disabled(model.busy || !model.profilesReady) }
            else { Button { model.showingNavigationDrawer = true } label: { Image(systemName: "sidebar.left") }.accessibilityLabel(AppText.localized("ナビゲーション")).accessibilityIdentifier("navigation-menu") }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if model.selected != nil {
                Button(action: model.replay) { Image(systemName: "speaker.wave.2") }.accessibilityLabel(AppText.localized("音声を再生")).accessibilityIdentifier("review-replay-audio")
                Button { updateWhiteboard { $0.toggleEnabled() } } label: { Image(systemName: whiteboardPreferences.enabled ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle") }.accessibilityLabel(AppText.localized("手書きボード")).accessibilityIdentifier("whiteboard-toggle")
                if whiteboard { Button { drawing = PKDrawing() } label: { Image(systemName: "trash") }.accessibilityLabel(AppText.localized("手書きを消す")) }
                Button(AppText.localized("取り消す"), action: undoStrokeOrReview).disabled(model.busy || !model.profilesReady).accessibilityIdentifier("review-undo")
                Menu {
                    Button(AppText.localized("やり直す")) { model.redo() }
                    Button(AppText.localized("自分の声を録音・再生"), systemImage: "mic") {
                        model.openReviewVoice()
                    }.disabled(model.card == nil || model.busy)
                    Button(AppText.localized("読み上げ音声を選択")) { model.openSpeechVoicePicker() }.accessibilityIdentifier("review-speech-choice")
                    Button(AppText.localized("ノートを追加")) { model.editorRequest = EditorRequest(deckID: model.selected?.id ?? "0") }
                    if whiteboardPreferences.enabled {
                        Button(whiteboardPreferences.visible ? AppText.localized("手書きを隠す") : AppText.localized("手書きを表示")) { updateWhiteboard { $0.toggleVisible() } }
                            .accessibilityIdentifier("whiteboard-visibility")
                    }
                    if whiteboard {
                        Button(whiteboardToolPicker ? AppText.localized("ペンの色・道具を隠す") : AppText.localized("ペンの色・道具を表示")) { whiteboardToolPicker.toggle() }
                            .accessibilityIdentifier("whiteboard-pen-palette")
                        Toggle(AppText.localized("消しゴム"), isOn: $eraser)
                        Toggle(AppText.localized("Apple Pencilのみで描く"), isOn: Binding(get: { whiteboardPreferences.stylusOnly }, set: { value in updateWhiteboard { $0.stylusOnly = value } }))
                            .accessibilityIdentifier("whiteboard-stylus-only")
                        Button(AppText.localized("手書きを画像で保存")) {
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
                    Button(model.card?.marked == true ? AppText.localized("マークを外す") : AppText.localized("マークを付ける"), systemImage: model.card?.marked == true ? "star.fill" : "star") { model.toggleCurrentMark() }
                    Button(AppText.localized("ノートを編集")) { if let card = model.card { model.editorRequest = EditorRequest(cardID: card.id, deckID: card.deckID) } }.accessibilityIdentifier("review-edit-note")
                    Toggle(AppText.localized("自動進行"), isOn: $model.autoAdvance).accessibilityIdentifier("auto-advance-toggle").onChange(of: model.autoAdvance) { _, _ in model.scheduleAutoAdvance() }
                    Button(AppText.localized("ユーザー操作")) {
                        templateActionKey = model.card?.mutationKey
                        model.showingTemplateActions = true
                    }.accessibilityIdentifier("template-actions-menu")
                    Button(AppText.localized("次のヒントを表示")) { model.showTemplateHint(all: false) }.accessibilityIdentifier("template-hint-next")
                    Button(AppText.localized("すべてのヒントを表示")) { model.showTemplateHint(all: true) }
                    Button(AppText.localized("タグを編集")) { openCardAction(.tags) }
                    Button(AppText.localized("期日を変更")) { openCardAction(.due) }
                    Button(AppText.localized("新規カードに戻す")) { openCardAction(.reset) }
                    Button(AppText.localized("カード情報")) { if let card = model.card { model.backendPage = BackendPageRequest(path: "card-info/" + card.id, title: AppText.localized("カード情報")) } }
                    Button(AppText.localized("保留")) { model.modifyCurrent { try await model.engine.suspend([$0.id]) } }
                    Button(AppText.localized("今日は表示しない")) { model.modifyCurrent { try await model.engine.bury([$0.id]) } }
                    Button(AppText.localized("関連カードを今日は表示しない")) { model.modifyCurrent { try await model.engine.bury([$0.noteID], note: true) } }
                    Menu(AppText.localized("フラグ")) {
                        ForEach(0..<8, id: \.self) { flag in Button(flag == 0 ? AppText.localized("なし") : AppText.localized("フラグ \(flag)")) { model.setCurrentFlag(flag) } }
                    }
                } label: { Image(systemName: "ellipsis.circle") }.disabled(model.busy || model.card == nil).accessibilityIdentifier("reviewer-menu")
            } else {
                Button(action: { model.synchronize() }) { Image(systemName: "arrow.triangle.2.circlepath") }
                    .accessibilityLabel(AppText.localized("AnkiWebと同期")).accessibilityIdentifier("sync")
                    .disabled(model.busy || !model.profilesReady)
                Button { model.showingAccount = true } label: { Image(systemName: "person.crop.circle") }
                    .accessibilityLabel(AppText.localized("AnkiWebアカウント")).accessibilityIdentifier("ankiweb-account")
                    .disabled(model.busy || !model.profilesReady)
                Button { model.editorRequest = EditorRequest() } label: { Image(systemName: "plus") }.accessibilityLabel(AppText.localized("ノートを追加")).accessibilityIdentifier("add-note").disabled(model.busy || !model.profilesReady)
                Menu {
                    Button(AppText.localized("カードブラウザー"), systemImage: "rectangle.stack") { model.browserSearch = ""; model.showingBrowser = true }.accessibilityIdentifier("browser-open")
                    Button(AppText.localized("テキストからノートを追加"), systemImage: "text.badge.plus") { addingTextNote = true }
                        .accessibilityIdentifier("add-text-note")
                    Button(AppText.localized("共有の受信トレイ"), systemImage: "tray") { showingSharedInbox = true }
                        .accessibilityIdentifier("shared-inbox-menu")
                    Button(AppText.localized("プロファイル"), systemImage: "person.2") { model.showingProfiles = true }.accessibilityIdentifier("profiles-open")
                    Button(AppText.localized("共有デッキを取得"), systemImage: "arrow.down.circle") { model.showingSharedDecks = true }.accessibilityIdentifier("shared-decks")
                    Button(AppText.localized("統計"), systemImage: "chart.bar") { model.backendPage = BackendPageRequest(path: "graphs", title: AppText.localized("統計")) }.accessibilityIdentifier("statistics")
                    Button(AppText.localized("フィルターデッキを作成")) { filteredDeck = FilteredDeckRequest() }
                    Button(AppText.localized("画像穴埋めを追加"), systemImage: "rectangle.dashed") { addingOcclusion = true }.accessibilityIdentifier("add-occlusion")
                    Button(AppText.localized("ノートタイプ"), systemImage: "rectangle.stack.badge.gearshape") { model.showingNoteTypes = true }.accessibilityIdentifier("notetypes")
                    Button(AppText.localized("設定"), systemImage: "gearshape") { model.showingSettings = true }
                    Button(AppText.localized("バックアップとチェック"), systemImage: "externaldrive") { model.showingMaintenance = true }
                    Button(AppText.localized("デッキを作成"), systemImage: "folder.badge.plus") { renamingDeck = nil; deckName = ""; namingDeck = true }
                    Button(AppText.localized("デッキを取り込む"), systemImage: "square.and.arrow.down") { importing = true }
                    Button(AppText.localized("すべて書き出す"), systemImage: "square.and.arrow.up", action: model.exportFile)
                    Button(AppText.localized("コレクションをすべて書き出す"), systemImage: "externaldrive.badge.plus", action: model.exportCollectionFile)
                    Button(AppText.localized("更新"), systemImage: "arrow.clockwise", action: model.refresh)
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
            .studyThemeSurface().navigationTitle(AppText.localized("カードの操作"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(AppText.localized("閉じる")) { model.showingReviewerOptions = false } } }
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
        case .info: if let card = model.card { model.backendPage = BackendPageRequest(path: "card-info/" + card.id, title: AppText.localized("カード情報")) }
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
                Button(AppText.localized("ユーザー操作 \(number)")) {
                    pendingTemplateAction = number
                    model.showingTemplateActions = false
                }.accessibilityIdentifier("template-action-\(number)")
            }
            .studyThemeSurface().navigationTitle(AppText.localized("ユーザー操作"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(AppText.localized("キャンセル")) { model.showingTemplateActions = false } } }
        }
    }
    private func finishTemplateAction() {
        defer { pendingTemplateAction = nil; templateActionKey = nil }
        guard let number = pendingTemplateAction, model.card?.mutationKey == templateActionKey else { return }
        model.performTemplateAction(number)
    }
    private var sheetContent: some View {
        navigationContent
        .sheet(isPresented: $model.showingNavigationDrawer, onDismiss: { model.finishNavigationSelection(); openPendingExternalRequest() }) { AppNavigationDrawerView(model: model) }
        .sheet(isPresented: $model.showingReviewVoice, onDismiss: {
            model.stopCardAudioForRecognition(); model.reviewVoice.finish()
            openPendingExternalRequest()
        }) { ReviewVoiceView(model: model, recorder: model.reviewVoice) }
        .sheet(item: model.speechRequestBinding(inVoice: false), onDismiss: { model.finishSpeechChoice(); openPendingExternalRequest() }) { request in
            ReviewSpeechVoiceView(model: model, request: request)
        }
        .sheet(isPresented: $model.showingTemplateActions, onDismiss: { finishTemplateAction(); openPendingExternalRequest() }) { templateActionPicker }
        .sheet(isPresented: $model.showingReviewerOptions, onDismiss: { finishReviewerPanelAction(); openPendingExternalRequest() }) { reviewerOptionsPanel }
        .sheet(isPresented: $model.showingNoteTypes, onDismiss: openPendingExternalRequest) { NoteTypeManagerView(model: model) }
        .sheet(isPresented: $model.showingSettings, onDismiss: openPendingExternalRequest) { SettingsView(model: model) }
        .sheet(isPresented: $model.showingMaintenance, onDismiss: openPendingExternalRequest) { MaintenanceView(model: model) }
        .sheet(item: $model.backendPage, onDismiss: openPendingExternalRequest) { BackendPageView(model: model, request: $0) }
        .sheet(item: $model.editorRequest, onDismiss: {
            activeSharedEditorReceipt?.deferUntilRequested(); activeSharedEditorReceipt = nil
            openPendingExternalRequest()
        }) { NoteEditorView(model: model, request: $0) }
        .sheet(isPresented: $showingSharedInbox, onDismiss: openPendingExternalRequest) {
            SharedInboxView(inbox: sharedInbox, profileName: model.currentProfile.name) { entry in
                guard model.profilesReady, !model.busy, !model.isSyncing else { return }
                prepareSharedEntry(entry)
                showingSharedInbox = false
            }
        }
        .sheet(isPresented: $model.showingProfiles, onDismiss: openPendingExternalRequest) { ProfileManagerView(model: model) }
        .sheet(isPresented: $model.showingSharedDecks, onDismiss: openPendingExternalRequest) { SharedDeckBrowserView(model: model) }
        .sheet(isPresented: $model.showingBrowser, onDismiss: {
            browserLinkSearch = nil; browserSessionActive = false; openPendingExternalRequest()
        }) { BrowserView(model: model, initialSearch: browserLinkSearch).onAppear { browserSessionActive = true } }
        .sheet(item: $model.cardActionRequest, onDismiss: openPendingExternalRequest) { ReviewCardActionsView(model: model, request: $0) }
        .sheet(item: $deckDescription, onDismiss: openPendingExternalRequest) { DeckDescriptionView(model: model, request: $0) }
        .sheet(item: $customStudy, onDismiss: openPendingExternalRequest) { CustomStudyView(model: model, request: $0) }
        .sheet(item: $filteredDeck, onDismiss: openPendingExternalRequest) { FilteredDeckView(model: model, request: $0) }
        .sheet(isPresented: $addingOcclusion, onDismiss: {
            receivedOcclusionFile?.receipt?.deferUntilRequested()
            receivedOcclusionFile = nil; openPendingExternalRequest()
        }) { ImageOcclusionEntryView(model: model, initialFile: receivedOcclusionFile?.file, sharedReceipt: receivedOcclusionFile?.receipt) }
        .sheet(isPresented: $addingTextNote, onDismiss: openPendingExternalRequest) {
            SharedTextEntryView { draft in
                guard addingTextNote else { return }
                pendingNoteActions.append(.edit(EditorRequest(initialDraft: draft)))
                addingTextNote = false
            }
        }
        .sheet(isPresented: $model.showingAccount, onDismiss: openPendingExternalRequest) { AccountView(model: model) }
        .sheet(item: $incomingFileReview, onDismiss: {
            activeIncomingReceipt?.deferUntilRequested(); activeIncomingReceipt = nil
            openPendingExternalRequest()
        }) { request in
            IncomingImportView(model: model, file: request.file) { action in
                let file = request.file
                guard incomingFileReview?.id == file.id, model.profilesReady, !model.busy, !model.isSyncing else { return }
                switch action {
                case .importDocument:
                    guard [.deck, .collection, .text].contains(file.kind) else { return }
                    model.importFile(file.url, retaining: file, sharedReceipt: request.receipt)
                case .attachToNote:
                    guard [.image, .audio, .video].contains(file.kind) else { return }
                    pendingNoteActions.append(.edit(EditorRequest(initialDraft: request.draft, incomingMedia: file, sharedReceipt: request.receipt)))
                case .imageOcclusion:
                    guard file.kind == .image else { return }
                    pendingNoteActions.append(.occlusion(request))
                }
                activeIncomingReceipt = nil // Ownership moves to the import/editor.
                incomingFileReview = nil
            }
        }
    }
    private var deckDialogContent: some View {
        sheetContent
        .alert(renamingDeck == nil ? AppText.localized("デッキを作成") : AppText.localized("デッキ名を変更"), isPresented: $namingDeck) {
            TextField(AppText.localized("デッキ名"), text: $deckName)
            Button(AppText.localized("保存")) {
                if let deck = renamingDeck { model.renameDeck(deck, name: deckName) }
                else { model.createDeck(deckName) }
            }.disabled(deckName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(AppText.localized("キャンセル"), role: .cancel) {}
        }
        .confirmationDialog(AppText.localized("デッキとカードを削除しますか？"), isPresented: Binding(get: { deletingDeck != nil }, set: { if !$0 { deletingDeck = nil } }), presenting: deletingDeck) { deck in
            Button(AppText.localized("削除"), role: .destructive) { model.deleteDeck(deck); deletingDeck = nil }
                .accessibilityIdentifier("deck-delete-confirm")
        } message: { _ in Text(AppText.localized("子デッキと関連するカードも削除します。バックアップを保存してから削除します。")) }
    }
    private var syncDialogContent: some View {
        deckDialogContent
        .alert(AppText.localized("従量課金の回線です"), isPresented: $model.meteredSyncPrompt) {
            Button(AppText.localized("続ける")) { model.synchronize(allowMeteredThisTime: true) }.accessibilityIdentifier("metered-sync-continue")
            Button(AppText.localized("今後は確認しない")) { model.allowMeteredSyncAlways() }
            Button(AppText.localized("キャンセル"), role: .cancel) {}
        } message: { Text(AppText.localized("モバイル回線などで同期すると、データ通信量がかかる場合があります。")) }
        .confirmationDialog(AppText.localized("同期するデータを選択"), isPresented: Binding(get: { model.chooseFullSync && !model.busy && phase == .active }, set: { model.chooseFullSync = $0 }), titleVisibility: .visible) {
            if let decision = model.syncDecision {
                if decision.canDownload { Button(AppText.localized("AnkiWebのデータをこのiPadにダウンロード"), role: .destructive) { model.confirmDirection = false } }
                if decision.canUpload { Button(AppText.localized("このiPadのデータをAnkiWebにアップロード"), role: .destructive) { uploadConfirmation = ""; model.confirmDirection = true } }
                Button(AppText.localized("キャンセル"), role: .cancel) { model.syncDecision = nil }
            }
        } message: { Text((model.syncDecision?.localSummary ?? "") + AppText.localized("\n一方のコレクション全体を使う必要があります。置き換える側だけの変更は失われます。")) }
        .alert(AppText.localized("データを置き換えますか？"), isPresented: Binding(get: { model.confirmDirection != nil }, set: { if !$0 { model.confirmDirection = nil } })) {
            if let upload = model.confirmDirection {
                if upload { TextField(AppText.localized("アップロード と入力"), text: $uploadConfirmation) }
                Button(AppText.localized("置き換えて同期"), role: .destructive) {
                    model.fullSync(upload: upload)
                    model.confirmDirection = nil
                    uploadConfirmation = ""
                }.disabled(upload && uploadConfirmation != AppText.localized("アップロード"))
            }
            Button(AppText.localized("キャンセル"), role: .cancel) { uploadConfirmation = ""; model.confirmDirection = nil; model.syncDecision = nil }
        } message: { Text((model.syncDecision?.localSummary ?? "") + "\n" + (model.confirmDirection == true ? AppText.localized("AnkiWebのコレクション全体を、このiPadのデータで置き換えます。AnkiWebだけにある変更は失われます。続ける場合は「アップロード」と入力してください。") : AppText.localized("このiPadのコレクションをAnkiWebのデータで置き換えます。取り込み前のローカルバックアップを保存します。"))) }
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
        .confirmationDialog(AppText.localized("コレクションを置き換えますか？"), isPresented: Binding(get: { model.pendingCollectionImport != nil }, set: { if !$0 { model.pendingCollectionImport = nil } })) {
            if let url = model.pendingCollectionImport { Button(AppText.localized("バックアップして置き換える"), role: .destructive) { model.importFile(url); model.pendingCollectionImport = nil } }
        } message: { Text(AppText.localized("現在のコレクションを読み込むファイルで置き換えます。現在のデータはバックアップに保存します。")) }
        .sheet(isPresented: Binding(get: { model.exportURL != nil }, set: { if !$0 { model.exportURL = nil } }), onDismiss: openPendingExternalRequest) {
            if let url = model.exportURL { ShareSheet(url: url) }
        }
    }
    private var errorContent: some View {
        importExportContent
        .alert(AppText.localized("処理できませんでした"), isPresented: Binding(get: { model.error != nil && !model.showingAccount }, set: { if !$0 { model.error = nil } })) {
            Button(AppText.localized("閉じる"), role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private func openPendingReminder() {
        guard model.profilesReady, !model.busy, phase == .active,
              !model.reviewingInteractionBlocked, let id = notificationRoute.take() else { return }
        guard model.profileRegistry.profiles.contains(where: { $0.id == id }) else {
            model.error = AppText.localized("通知のプロファイルが見つかりません。削除済みの可能性があります。")
            return
        }
        openingReminder = true
        Task {
            defer { openingReminder = false; openPendingExternalRequest() }
            do {
                try await model.switchProfile(id)
                if model.selected != nil { model.leave() }
            } catch { model.error = error.localizedDescription }
        }
    }
    private var canPresentExternalRequest: Bool {
        model.profilesReady && !model.busy && !model.isSyncing && phase == .active
            && !model.reviewingInteractionBlocked && !localCollectionPresentationActive
            && !model.chooseFullSync && model.confirmDirection == nil && !model.meteredSyncPrompt
            && !openingReminder && !browserSessionActive && notificationRoute.profileID == nil
    }
    private func openPendingExternalRequest() {
        guard pendingWidgetRoute != nil || !incomingFiles.isEmpty || !pendingNoteActions.isEmpty || browserLinks.pending != nil || sharedInbox.nextAutomaticEntry != nil,
              canPresentExternalRequest else { return }
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        // Model bindings can clear before a sheet's dismissal animation ends.
        // Its onDismiss retries after the real controller has gone away.
        guard let root = window?.rootViewController, root.presentedViewController == nil else { return }
        if let route = pendingWidgetRoute {
            pendingWidgetRoute = nil
            Task {
                guard canPresentExternalRequest else {
                    if pendingWidgetRoute == nil { pendingWidgetRoute = route }
                    return
                }
                do { try await model.openWidgetRoute(route) }
                catch { model.error = error.localizedDescription }
                openPendingExternalRequest()
            }
            return
        }
        if !pendingNoteActions.isEmpty {
            switch pendingNoteActions.removeFirst() {
            case .edit(let request): activeSharedEditorReceipt = request.sharedReceipt; model.editorRequest = request
            case .occlusion(let file): receivedOcclusionFile = file; addingOcclusion = true
            }
            return
        }
        if !incomingFiles.isEmpty {
            let request = incomingFiles.removeFirst()
            activeIncomingReceipt = request.receipt
            incomingFileReview = request
            return
        }
        guard incomingFileCopies == 0 else { return }
        if let request = browserLinks.take(canPresent: true) {
            browserLinkSearch = request.search
            model.showingBrowser = true
        } else if let entry = sharedInbox.nextAutomaticEntry {
            prepareSharedEntry(entry)
            openPendingExternalRequest()
        }
    }
    private func prepareSharedEntry(_ entry: SharedInboxEntry) {
        guard entry.transfer.attachments.count <= 1, let receipt = sharedInbox.begin(entry) else { return }
        let draft = entry.transfer.text.map { IncomingNoteDraft(subject: $0.subject, text: $0.text, tags: $0.tags, isHTML: $0.isHTML) }
        guard let attachment = entry.transfer.attachments.first else {
            if let draft { pendingNoteActions.append(.edit(EditorRequest(initialDraft: draft, sharedReceipt: receipt))) }
            else { receipt.deferUntilRequested() }
            return
        }
        incomingFileCopies += 1
        Task {
            defer { incomingFileCopies -= 1; openPendingExternalRequest() }
            do {
                let file = try await IncomingImportStager.shared.copy(entry.file(attachment), name: attachment.originalName, typeIdentifier: attachment.typeIdentifier)
                incomingFiles.append(ReceivedRequest(file: file, receipt: receipt, draft: draft))
            } catch {
                receipt.deferUntilRequested()
                model.error = error.localizedDescription
            }
        }
    }
    private func receiveExternalURL(_ url: URL) {
        if let route = WidgetRoute(url: url) {
            pendingWidgetRoute = route
            openPendingExternalRequest()
        } else if url.isFileURL {
            incomingFileCopies += 1
            Task {
                do {
                    let file = try await IncomingImportStager.shared.copy(url)
                    incomingFiles.append(ReceivedRequest(file: file))
                } catch { model.error = error.localizedDescription }
                incomingFileCopies -= 1
                openPendingExternalRequest()
            }
        } else if let draft = IncomingNoteDraft(url: url) {
            pendingNoteActions.append(.edit(EditorRequest(initialDraft: draft)))
            openPendingExternalRequest()
        } else if browserLinks.receive(url) { openPendingExternalRequest() }
    }
    private var observedContent: some View {
        errorContent
        .task { model.bootstrap(); sharedInbox.refresh(); openPendingReminder(); openPendingExternalRequest(); model.requestAutomaticSync(.foreground) }
        .onChange(of: sharedInbox.entries.map(\.id)) { _, _ in openPendingExternalRequest() }
        .onOpenURL(perform: receiveExternalURL)
        .onChange(of: canPresentExternalRequest) { _, ready in if ready { openPendingExternalRequest() } }
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
            if value == .active { sharedInbox.refresh(); model.scheduleWidgetRefresh(force: true); model.resumeReviewScene(); openPendingReminder(); model.requestAutomaticSync(.foreground) }
        }
        .onChange(of: model.reviewingInteractionBlocked) { _, blocked in
            if blocked { model.pauseReviewInteraction() } else { model.resumeReviewInteraction(); model.scheduleConditionalReminderRefresh(); openPendingReminder(); model.processPendingAutomaticSync() }
        }
        .alert(AppText.localized("学習の区切り"), isPresented: Binding(get: { model.timeboxReport != nil && !model.busy && phase == .active }, set: { if !$0 { model.timeboxReport = nil } })) {
            Button(AppText.localized("続ける")) { model.timeboxReport = nil }.accessibilityIdentifier("timebox-continue")
            Button(AppText.localized("学習を終了")) { model.leave() }.accessibilityIdentifier("timebox-finish")
        } message: { Text(model.timeboxReport?.message ?? "") }
        .alert(AppText.localized("自動進行"), isPresented: $model.timedReminder) { Button(AppText.localized("閉じる"), role: .cancel) {} } message: { Text(AppText.localized("カードの表示時間が終了しました。解答または評価を選んでください。")) }
    }
    private var localCollectionPresentationActive: Bool {
        importing || addingOcclusion || addingTextNote || showingSharedInbox || customStudy != nil || filteredDeck != nil || deckDescription != nil
            || namingDeck || deletingDeck != nil || model.pendingCollectionImport != nil || incomingFileReview != nil
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
                        .accessibilityLabel(deck.collapsed ? AppText.localized("\(deck.name)を展開") : AppText.localized("\(deck.name)を折りたたむ"))
                            .accessibilityValue(deck.collapsed ? AppText.localized("折りたたみ") : AppText.localized("展開"))
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
                            Button(AppText.localized("デッキの説明")) { deckDescription = DeckDescriptionRequest(deck: deck) }
                            if deck.filtered {
                                Button(AppText.localized("フィルターデッキを編集")) { filteredDeck = FilteredDeckRequest(deckID: deck.id) }
                                Button(AppText.localized("フィルターデッキを再構築")) { model.run { _ = try await model.engine.call("SchedulerService.RebuildFilteredDeck", ["did": deck.id]); model.refreshAfterEditing() } }
                                Button(AppText.localized("フィルターデッキを空にする")) { model.run { _ = try await model.engine.call("SchedulerService.EmptyFilteredDeck", ["did": deck.id]); model.refreshAfterEditing() } }
                            } else {
                                Button(AppText.localized("カスタム学習")) { customStudy = CustomStudyRequest(deck: deck) }
                            }
                            Button(AppText.localized("デッキオプション")) { model.backendPage = BackendPageRequest(path: "deck-options/" + deck.id, title: AppText.localized("デッキオプション")) }
                            Button(AppText.localized("統計")) { model.run { try await model.engine.select(deck.id); model.backendPage = BackendPageRequest(path: "graphs", title: AppText.localized("統計")) } }
                            Button(AppText.localized("名前を変更")) { renamingDeck = deck; deckName = deck.name; namingDeck = true }
                            Button(AppText.localized("ノートを追加")) { model.editorRequest = EditorRequest(deckID: deck.id) }.accessibilityIdentifier("deck-add-note-\(deck.id)")
                            Button(AppText.localized("削除"), role: .destructive) { deletingDeck = deck }
                        }
                    }.padding(.leading, CGFloat(deck.level) * 16)
                        .listRowBackground(deck.isSelected
                            ? activeTheme.selectedDeckBackground.opacity(currentDeckBackground == nil ? 1 : 114.0 / 255)
                            : deckRowBackground)
                }
            } header: { Text(AppText.localized("デッキ                         新規 · 学習 · 復習")) }
            .listRowBackground(deckRowBackground)
            Section {
                if let account = model.account {
                    Text(account.username).font(.subheadline)
                    if let date = model.lastSync { Text(AppText.localized("最終同期: \(date.formatted(.dateTime.locale(AppText.locale)))")).font(.caption).foregroundStyle(.secondary) }
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--uitest-sync-timing"), let date = model.lastSync {
                        Text(String(date.timeIntervalSince1970)).accessibilityIdentifier("sync-completed-at")
                    }
                    if ProcessInfo.processInfo.arguments.contains("--uitest-sync-timing"), let date = model.debugBackgroundSyncCompletedAt {
                        Text(String(date.timeIntervalSince1970)).accessibilityIdentifier("background-sync-completed-at")
                    }
                    #endif
                } else {
                    Button(AppText.localized("AnkiWebにログイン")) { model.showingAccount = true }.accessibilityIdentifier("login-entry")
                }
                if !model.syncStatus.isEmpty { Text(model.syncStatus).font(.caption).foregroundStyle(.secondary) }
                if model.syncDecision != nil {
                    Text(AppText.localized("同期方向の確認が必要です")).accessibilityIdentifier("sync-direction-pending")
                } else if model.localSyncState?.hasChanges == true {
                    if showSyncStatusBadge {
                        Label(AppText.localized("未同期の変更があります"), systemImage: "arrow.triangle.2.circlepath").accessibilityIdentifier("sync-local-changes")
                    }
                } else if model.mediaSyncPending {
                    Text(AppText.localized("同期が完了していません")).font(.caption).accessibilityIdentifier("sync-media-pending")
                } else if model.localSyncState?.neverSynced == true {
                    Text(AppText.localized("まだ同期していません")).font(.caption)
                } else if model.localSyncState == nil && !model.busy {
                    Text(AppText.localized("ローカルの同期状態を確認できませんでした")).font(.caption)
                }
                Button(AppText.localized(".apkgファイルを取り込む"), systemImage: "square.and.arrow.down") { importing = true }.disabled(model.busy || !model.profilesReady)
                Text(AppText.localized("AnkiDroidまたはAnkiから書き出したデッキを読み込めます。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }.listRowBackground(deckRowBackground)
        }
        .searchable(text: $deckSearch, prompt: AppText.localized("デッキを検索"))
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
                    Text(AppText.localized("解答を表示")).font(.system(size: answerFontSize * answerScale))
                    if answerHoldMilliseconds > 0 { Text(AppText.localized("\(answerHoldMilliseconds)ミリ秒長押し")).font(.caption) }
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
            ContentUnavailableView(AppText.localized("このデッキの学習は終了です"), systemImage: "checkmark.circle", description: Text(AppText.localized("デッキ一覧に戻って、別のデッキを選べます。")))
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
