import SwiftUI
import UniformTypeIdentifiers
import PencilKit

@main struct AnkiPadApp: App {
    @UIApplicationDelegateAdaptor(ReviewNotificationAppDelegate.self) private var notificationDelegate
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        WindowGroup { ContentView().preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil) }
    }
}

@MainActor final class StudyModel: ObservableObject {
    @Published var engine = Engine()
    let profileStore = ProfileRegistryStore()
    @Published var profileRegistry = ProfileRegistry.initial
    @Published var profilesReady = false
    @Published var showingProfiles = false
    private var deferredProfileImport: URL?
    private let audio = CardAudio()
    let cardSpeech = CardScriptSpeech()
    let cardRecognition = CardScriptRecognition()
    @Published var cardScriptEvents: [CardScriptEvent] = []
    let networkMetering = NetworkMetering()
    var cardAPIDenials = 0
    @Published var decks: [Deck] = []
    @Published var card: StudyCard?
    @Published var selected: Deck?
    @Published var revealed = false
    @Published var typedAnswer = ""
    @Published var answerOverride: String?
    @Published var autoAdvance = false
    @Published var reviewDisplayMode = ReviewDisplayMode(rawValue: UserDefaults.standard.integer(forKey: "reviewDisplayMode")) ?? .buttonsAndMenu {
        didSet { UserDefaults.standard.set(reviewDisplayMode.rawValue, forKey: "reviewDisplayMode") }
    }
    @Published var showReviewTopbar = UserDefaults.standard.object(forKey: "showReviewTopbar") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showReviewTopbar, forKey: "showReviewTopbar") }
    }
    @Published var timedReminder = false
    @Published var cardToast: String?
    private var toastTask: Task<Void, Never>?
    @Published var schedulerReady = true
    private var autoTask: Task<Void, Never>?
    private var stoppedAt: Date?
    private var interactionPauseStarted: Date?
    private var pausedReviewSeconds: TimeInterval = 0
    private var pendingQuestionAudio = false
    @Published private var reviewSceneActive = true
    @Published var busy = false
    @Published var cardDialogPresented = false
    @Published var error: String?
    @Published var exportURL: URL?
    @Published var finished = false
    @Published var account: SyncCredentials?
    @Published var showingAccount = false
    @Published var showingBrowser = false
    @Published var showingSharedDecks = false
    @Published var showingNavigationDrawer = false
    @Published var showingReviewerOptions = false
    @Published var showingTemplateActions = false
    @Published var showingReviewVoice = false
    let reviewVoice = NoteAudioRecorder()
    var pendingNavigationChoice: AppNavigationChoice?
    @Published var showingSettings = false
    @Published var showingNoteTypes = false
    @Published var showingMaintenance = false
    @Published var pendingCollectionImport: URL?
    @Published var browserSearch = ""
    @Published var editorRequest: EditorRequest?
    @Published var cardActionRequest: ReviewCardActionRequest?
    @Published var backendPage: BackendPageRequest?
    @Published var isSyncing = false
    @Published var syncStatus = ""
    @Published var chooseFullSync = false
    @Published var syncDecision: SyncDecision?
    @Published var confirmDirection: Bool?
    @Published var lastSync: Date?
    private var syncCancelled = false
    private var started = Date()

    func run(_ operation: @escaping () async throws -> Void) {
        guard profilesReady, !busy else { return }
        busy = true
        syncCancelled = false
        Task {
            defer { busy = false; isSyncing = false }
            do { try await operation() }
            catch {
                if let failure = error as? EngineError, failure.kind == 7 {
                    try? AccountStore.delete(profileID: self.currentProfileID)
                    account = nil
                    showingAccount = true
                }
                if !syncCancelled { self.error = error.localizedDescription }
            }
        }
    }
    func bootstrap() {
        guard !profilesReady else { return }
        do {
            let registry = try profileStore.load()
            engine = Engine(root: try profileStore.root(for: registry.selectedID))
            profileRegistry = registry
            profilesReady = true
        } catch { self.error = error.localizedDescription; return }
        do { account = try AccountStore.load(profileID: currentProfileID) }
        catch { self.error = error.localizedDescription }
        lastSync = UserDefaults.standard.object(forKey: profilePreferenceKey("lastSync")) as? Date
        if let deferredProfileImport { self.deferredProfileImport = nil; importFile(deferredProfileImport); return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest-fixture"),
           let fixture = Bundle.main.url(forResource: "fixture", withExtension: "apkg") {
            importFile(fixture)
            return
        }
        #endif
        refresh()
    }
    func login(username: String, password: String, endpoint: String?) {
        run {
            self.isSyncing = true
            self.syncStatus = "AnkiWebにログイン中…"
            let credentials = try await self.engine.login(username: username, password: password, endpoint: endpoint)
            guard !self.syncCancelled else { throw CancellationError() }
            try AccountStore.save(credentials, profileID: self.currentProfileID)
            self.account = credentials
            self.showingAccount = false
            try await self.performSync()
        }
    }
    func logout() {
        guard !busy else { return }
        do {
            try AccountStore.delete(profileID: self.currentProfileID)
            account = nil
            lastSync = nil
            syncStatus = ""
            UserDefaults.standard.removeObject(forKey: profilePreferenceKey("lastSync"))
        } catch { self.error = error.localizedDescription }
    }
    func synchronize() {
        guard account != nil else { showingAccount = true; return }
        run { try await self.performSync() }
    }
    private func performSync() async throws {
        guard let account else { return }
        isSyncing = true
        audio.stop()
        cardSpeech.stop()
        cardRecognition.cancel()
        cardScriptEvents.removeAll()
        autoTask?.cancel()
        selected = nil
        pendingQuestionAudio = false
        card = nil
        syncStatus = "コレクションを同期中…"
        let decision = try await engine.sync(account)
        if let endpoint = decision.endpoint {
            var updated = account
            updated.endpoint = endpoint
            try AccountStore.save(updated, profileID: self.currentProfileID)
            self.account = updated
        }
        if !decision.message.isEmpty { syncStatus = decision.message }
        if decision.needsFull {
            if decision.automaticallyDownload {
                syncStatus = "空のコレクションにAnkiWebからダウンロード中…"
                try await engine.fullSync(self.account ?? account, upload: false, serverUSN: decision.serverUSN)
                try await finishMediaSync()
                return
            }
            guard decision.canUpload || decision.canDownload else {
                throw EngineError(message: "安全な同期方向を確認できませんでした。AnkiWebへのアップロードは行っていません。")
            }
            syncDecision = decision
            syncStatus = "同期するデータを選択してください"
            if decision.required == "FULL_UPLOAD" { confirmDirection = true }
            else { chooseFullSync = true }
            return
        }
        try await finishMediaSync()
    }
    func fullSync(upload: Bool) {
        guard let decision = syncDecision, let account,
              upload ? decision.canUpload : decision.canDownload else { return }
        run {
            self.isSyncing = true
            self.syncStatus = upload ? "AnkiWebにアップロード中…" : "AnkiWebからダウンロード中…"
            self.syncDecision = nil
            try await self.engine.fullSync(account, upload: upload, serverUSN: decision.serverUSN)
            try await self.finishMediaSync()
        }
    }
    private func finishMediaSync() async throws {
        syncStatus = "画像・音声を同期中…"
        while true {
            let status = try await engine.mediaSyncStatus()
            if let progress = status["progress"] as? [String: Any] {
                syncStatus = [progress["checked"], progress["added"], progress["removed"]].compactMap { $0 as? String }.joined(separator: " · ")
            }
            if status["active"] as? Bool != true { break }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        decks = try await engine.decks()
        lastSync = Date()
        UserDefaults.standard.set(lastSync, forKey: profilePreferenceKey("lastSync"))
        syncStatus = "同期しました"
    }
    func cancelSync() {
        guard isSyncing else { return }
        syncCancelled = true
        Task {
            do { try await engine.abortSync(); syncStatus = "同期を中止しました" }
            catch { self.error = error.localizedDescription }
        }
    }
    func refreshAfterEditing() {
        run {
            self.decks = try await self.engine.decks()
            if self.selected != nil { self.audio.stop(); try await self.loadNext() }
        }
    }
    var reviewingInteractionBlocked: Bool {
        !reviewSceneActive || cardDialogPresented || showingAccount || showingBrowser || showingSharedDecks || showingProfiles || showingSettings || showingMaintenance || showingNoteTypes
        || showingNavigationDrawer || showingReviewerOptions || showingTemplateActions || showingReviewVoice || editorRequest != nil || backendPage != nil
        || cardActionRequest != nil || exportURL != nil || error != nil
    }
    func pauseReviewInteraction() {
        autoTask?.cancel()
        if card != nil, stoppedAt == nil, interactionPauseStarted == nil { interactionPauseStarted = Date() }
    }
    func resumeReviewInteraction() {
        guard reviewSceneActive, !reviewingInteractionBlocked else { return }
        if let paused = interactionPauseStarted { pausedReviewSeconds += Date().timeIntervalSince(paused); interactionPauseStarted = nil }
        if pendingQuestionAudio, !revealed, let card {
            pendingQuestionAudio = false
            if card.options.autoplay { audio.play(card.questionAV, media: engine.media) }
        }
        scheduleAutoAdvance()
    }
    func pauseReviewScene() { reviewSceneActive = false; pauseReviewInteraction() }
    func resumeReviewScene() { reviewSceneActive = true; resumeReviewInteraction() }
    func openReviewVoice() {
        guard card != nil, !busy else { return }
        stopCardAudioForRecognition()
        cardRecognition.cancel()
        showingReviewVoice = true
    }
    func stopCardAudioForRecognition() { audio.stop(); cardSpeech.stop() }
    func showCardToast(_ text: String, short: Bool) {
        toastTask?.cancel()
        cardToast = text
        UIAccessibility.post(notification: .announcement, argument: text)
        toastTask = Task {
            do { try await Task.sleep(nanoseconds: short ? 2_000_000_000 : 3_500_000_000) }
            catch { return }
            cardToast = nil
        }
    }
    func reloadAfterCardAPIMutation() async throws {
        audio.stop()
        try await loadNext()
        decks = try await engine.decks()
    }
    func setCurrentFlag(_ flag: Int) {
        guard let current = card else { return }
        run {
            try await self.engine.setFlag([current.id], flag: flag)
            if self.card?.id == current.id { self.card?.flag = flag }
        }
    }
    func toggleCurrentMark() {
        guard let current = card else { return }
        run {
            try await self.engine.tagNotes([current.noteID], tags: "marked", remove: current.marked)
            if self.card?.id == current.id { self.card?.marked = !current.marked }
        }
    }
    func modifyCurrent(_ operation: @escaping (StudyCard) async throws -> Void) {
        guard let card else { return }
        run {
            self.audio.stop()
            try await operation(card)
            try await self.loadNext()
            self.decks = try await self.engine.decks()
        }
    }
    func createDeck(_ name: String) { run { try await self.engine.createDeck(name); self.decks = try await self.engine.decks() } }
    func renameDeck(_ deck: Deck, name: String) { run { try await self.engine.renameDeck(deck.id, name: name); self.decks = try await self.engine.decks() } }
    func deleteDeck(_ deck: Deck) { run { try await self.engine.backup(); try await self.engine.removeDeck(deck.id); self.decks = try await self.engine.decks() } }
    func refresh() { run { self.decks = try await self.engine.decks() } }
    func select(_ deck: Deck) {
        run {
            self.audio.stop()
            try await self.engine.select(deck.id)
            self.selected = deck
            try await self.loadNext()
        }
    }
    private func loadNext() async throws {
        reviewVoice.finish()
        reviewVoice.discard()
        cardSpeech.stop()
        cardRecognition.cancel()
        cardScriptEvents.removeAll()
        // Clear the old card before fetching: a failed fetch must never allow a second answer.
        card = nil
        revealed = false
        typedAnswer = ""
        answerOverride = nil
        finished = false
        card = try await engine.next()
        schedulerReady = card?.customScheduling.isEmpty ?? true
        started = Date()
        UIApplication.shared.isIdleTimerDisabled = UserDefaults.standard.object(forKey: "keepScreenOn") as? Bool ?? true
        stoppedAt = nil
        pausedReviewSeconds = 0
        interactionPauseStarted = reviewingInteractionBlocked && card != nil ? Date() : nil
        pendingQuestionAudio = false
        finished = card == nil
        if let card {
            if reviewingInteractionBlocked { pendingQuestionAudio = card.options.autoplay }
            else if card.options.autoplay { audio.play(card.questionAV, media: engine.media) }
            scheduleAutoAdvance()
        }
    }
    func reveal() {
        guard !busy, !reviewingInteractionBlocked, schedulerReady, let card else { return }
        run {
            self.answerOverride = try await self.engine.compareTyped(card, provided: self.typedAnswer)
            self.revealed = true
            if card.options.stopTimerOnAnswer { self.stoppedAt = Date() }
            if card.options.interruptAudio { self.audio.stop() }
            if card.options.autoplay { self.audio.append(card.answerAV, media: self.engine.media) }
            self.scheduleAutoAdvance()
        }
    }
    func replay() {
        guard let card else { return }
        let tags = revealed ? ((card.options.replayQuestion ? card.questionAV : []) + card.answerAV) : card.questionAV
        audio.play(tags, media: engine.media)
    }
    func answer(_ rating: Int) {
        guard revealed, !reviewingInteractionBlocked, schedulerReady, let card else { return }
        run {
            self.audio.stop()
            try await self.engine.answer(card, rating: rating, elapsed: self.elapsed())
            try await self.loadNext()
            self.decks = try await self.engine.decks()
        }
    }
    func redo() {
        run {
            self.audio.stop()
            _ = try await self.engine.call("CollectionService.Redo")
            if self.selected != nil { try await self.loadNext() }
            self.decks = try await self.engine.decks()
        }
    }
    func undo() {
        run {
            self.audio.stop()
            try await self.engine.undo()
            if self.selected != nil { try await self.loadNext() }
            self.decks = try await self.engine.decks()
        }
    }
    func importFile(_ url: URL) {
        guard profilesReady else { deferredProfileImport = url; return }
        run {
            self.audio.stop()
            self.cardSpeech.stop()
            self.cardRecognition.cancel()
            self.cardScriptEvents.removeAll()
            self.autoTask?.cancel()
            self.pendingQuestionAudio = false
            self.selected = nil
            self.card = nil
            switch url.pathExtension.lowercased() {
            case "colpkg": try await self.engine.restoreCollection(url)
            case "csv", "tsv", "txt":
                let local = try await self.engine.prepareImport(url)
                var allowed = CharacterSet.urlPathAllowed
                allowed.remove(charactersIn: "/")
                let path = local.path.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                self.backendPage = BackendPageRequest(path: "import-csv/" + path, title: "テキストを取り込む")
            default: try await self.engine.importPackage(url)
            }
            self.decks = try await self.engine.decks()
        }
    }
    func exportFile() { run { self.exportURL = try await self.engine.exportPackage() } }
    func exportCollectionFile() { run { self.exportURL = try await self.engine.exportCollection() } }
    func playTag(answer: Bool, index: Int) {
        guard let card else { return }
        let tags = answer ? card.answerAV : card.questionAV
        guard tags.indices.contains(index) else { return }
        audio.play([tags[index]], media: engine.media)
    }
    func schedulingRequest(_ method: String, input: String, key: String) async throws -> String {
        guard let current = card, current.mutationKey == key, !revealed else { throw EngineError(message: "学習対象のカードが変わりました。") }
        if method == "getSchedulingStatesWithContext" {
            return try await engine.call("_encode/get_scheduling_states_with_context", ["states": current.states, "context": current.context])["data"] as? String ?? ""
        }
        guard method == "setSchedulingStates" else { throw EngineError(message: "未対応のスケジューラー操作です。") }
        let request = try await engine.call("_decode/set_scheduling_states", ["data": input])
        guard request["key"] as? String == key, let states = request["states"] as? [String: Any] else { throw EngineError(message: "スケジューラーの応答が一致しません。") }
        let labels = try await engine.call("SchedulerService.DescribeNextStates", states)
        guard var updated = card, updated.mutationKey == key, !revealed else { throw EngineError(message: "学習対象のカードが変わりました。") }
        updated.states = states
        updated.intervals = labels["vals"] as? [String] ?? []
        card = updated
        schedulerReady = true
        scheduleAutoAdvance()
        return ""
    }
    func schedulingFailed(_ message: String, key: String) {
        guard card?.mutationKey == key, !revealed, !schedulerReady else { return }
        schedulerReady = true
        error = "カスタムスケジューラーを適用できませんでした。標準の学習状態を使います。\n" + message
    }
    func elapsed() -> TimeInterval { max(0, (stoppedAt ?? interactionPauseStarted ?? Date()).timeIntervalSince(started) - pausedReviewSeconds) }
    func scheduleAutoAdvance() {
        autoTask?.cancel()
        guard autoAdvance, schedulerReady, !reviewingInteractionBlocked, let card else { return }
        let isAnswer = revealed
        let delay = isAnswer ? card.options.answerSeconds : card.options.questionSeconds
        guard delay > 0 else { return }
        autoTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(min(delay, 86400) * 1_000_000_000))
                while card.options.waitForAudio && audio.isPlaying { try await Task.sleep(nanoseconds: 100_000_000) }
                try Task.checkCancellation()
                guard self.card?.mutationKey == card.mutationKey, revealed == isAnswer, !busy, !reviewingInteractionBlocked else { return }
                if !isAnswer {
                    if card.options.questionAction == "QUESTION_ACTION_SHOW_REMINDER" { timedReminder = true }
                    else { reveal() }
                } else {
                    switch card.options.answerAction {
                    case "ANSWER_ACTION_ANSWER_AGAIN": answer(0)
                    case "ANSWER_ACTION_ANSWER_GOOD": answer(2)
                    case "ANSWER_ACTION_ANSWER_HARD": answer(1)
                    case "ANSWER_ACTION_SHOW_REMINDER": timedReminder = true
                    default: modifyCurrent { try await self.engine.bury([$0.id]) }
                    }
                }
            } catch {}
        }
    }
    func replayStop() { reviewVoice.finish(); pauseReviewScene(); cardRecognition.cancel(); cardSpeech.stop(); audio.stop(); autoTask?.cancel(); UIApplication.shared.isIdleTimerDisabled = false }
    func leave() {
        showingReviewVoice = false
        reviewVoice.finish()
        reviewVoice.discard()
        cardSpeech.stop()
        cardRecognition.cancel()
        cardScriptEvents.removeAll()
        audio.stop()
        selected = nil
        pendingQuestionAudio = false
        card = nil
        autoTask?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
        refresh()
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
