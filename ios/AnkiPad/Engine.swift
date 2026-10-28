import Foundation

struct EngineError: LocalizedError {
    let message: String
    var kind: Int? = nil
    var errorDescription: String? { message }
}
struct StudyCard {
    let id: String
    let noteID: String
    let deckID: String
    let ordinal: Int
    var flag: Int
    var marked: Bool
    let typing: TypedAnswerSpec?
    let options: ReviewOptions
    let question: String
    let answer: String
    let css: String
    var states: [String: Any]
    var intervals: [String]
    let context: [String: Any]
    let customScheduling: String
    let mutationKey: String
    let questionAV: [[String: Any]]
    let answerAV: [[String: Any]]
    let counts: String
}

actor Engine {
    private var transport: BackendTransport?
    private var opened = false
    private var syncAbortRequested = false
    private var activeSyncCall: UUID?
    var stickyFieldValues: [String: [String: String]] = [:]
    nonisolated let root: URL
    nonisolated var media: URL { root.appendingPathComponent("collection.media", isDirectory: true) }

    init(root profileRoot: URL? = nil) {
        root = profileRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AnkiPad", isDirectory: true)
    }
    func close() throws {
        if opened { _ = try raw("CollectionService.CloseCollection") }
        opened = false
        transport = nil
    }
    private func start() throws {
        guard !opened else { return }
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        if transport == nil { transport = try BackendTransport() }
        _ = try raw("CollectionService.OpenCollection", [
            "collectionPath": root.appendingPathComponent("collection.anki2").path,
            "mediaFolderPath": media.path,
            "mediaDbPath": root.appendingPathComponent("collection.media.db2").path
        ])
        opened = true
    }
    private func raw(_ method: String, _ args: [String: Any] = [:]) throws -> [String: Any] {
        guard let transport else { throw EngineError(message: "学習エンジンが閉じられています。") }
        return try transport.call(method, args)
    }
    func longCall(_ method: String, _ args: [String: Any]) async throws -> [String: Any] {
        try start()
        let isSyncCall = method.hasPrefix("SyncService.")
        if isSyncCall && syncAbortRequested { throw CancellationError() }
        let callID = UUID()
        if isSyncCall { activeSyncCall = callID }
        defer { if activeSyncCall == callID { activeSyncCall = nil } }
        let transport = self.transport!
        return try await Task.detached(priority: .userInitiated) { try transport.call(method, args) }.value
    }
    func call(_ method: String, _ args: [String: Any] = [:]) throws -> [String: Any] {
        try start()
        return try raw(method, args)
    }
    func decks() throws -> [Deck] {
        let tree = try call("DecksService.DeckTree", ["now": String(Int64(Date().timeIntervalSince1970))])
        return Deck.flatten(tree["children"] as? [[String: Any]] ?? [])
    }
    func setDeckCollapsed(_ id: String, collapsed: Bool) throws {
        _ = try call("DecksService.SetDeckCollapsed", ["deckId": id, "collapsed": collapsed, "scope": "REVIEWER"])
    }

    func select(_ id: String) throws { _ = try call("DecksService.SetCurrentDeck", ["did": id]) }
    func next() throws -> StudyCard? {
        let queue = try call("SchedulerService.GetQueuedCards", ["fetchLimit": 1])
        guard let queued = (queue["cards"] as? [[String: Any]])?.first,
              let card = queued["card"] as? [String: Any], let id = card["id"] as? String,
              var states = queued["states"] as? [String: Any] else { return nil }
        if let customData = card["customData"] as? String {
            for key in ["current", "again", "hard", "good", "easy"] {
                var state = states[key] as? [String: Any] ?? [:]
                state["customData"] = customData
                states[key] = state
            }
        }
        let rendered = try call("CardRenderingService.RenderExistingCard", ["cardId": id, "partialRender": true])
        func text(_ key: String, front: String? = nil) throws -> String {
            let nodes = rendered[key] as? [[String: Any]] ?? []
            return try nodes.map { node in
                if let text = node["text"] as? String { return text }
                if let replacement = node["replacement"] as? [String: Any], replacement["fieldName"] as? String == "FrontSide" { return front ?? "" }
                throw EngineError(message: "このカードには未対応のテンプレートフィルターがあります。")
            }.joined()
        }
        let q = try call("CardRenderingService.ExtractAvTags", ["text": try text("questionNodes"), "questionSide": true])
        let a = try call("CardRenderingService.ExtractAvTags", ["text": try text("answerNodes", front: q["text"] as? String ?? ""), "questionSide": false])
        let descriptions = try call("SchedulerService.DescribeNextStates", states)
        let customScheduling = try call("ConfigService.GetConfigString", ["key": "CARD_STATE_CUSTOMIZER"])["val"] as? String ?? ""
        let options = try reviewOptions(card: card)
        let typing = try typingSpec(question: q["text"] as? String ?? "", noteID: card["noteId"] as? String ?? "0", ordinal: card["templateIdx"] as? Int ?? 0)
        let note = try call("NotesService.GetNote", ["nid": card["noteId"] as? String ?? "0"])
        return StudyCard(id: id, noteID: card["noteId"] as? String ?? "0", deckID: card["deckId"] as? String ?? "1", ordinal: card["templateIdx"] as? Int ?? 0, flag: (card["flags"] as? Int ?? 0) & 7, marked: (note["tags"] as? [String] ?? []).contains(where: { $0.lowercased() == "marked" }), typing: typing, options: options, question: q["text"] as? String ?? "", answer: a["text"] as? String ?? "",
            css: rendered["css"] as? String ?? "", states: states, intervals: descriptions["vals"] as? [String] ?? [],
            context: queued["context"] as? [String: Any] ?? [:], customScheduling: customScheduling, mutationKey: UUID().uuidString,
            questionAV: q["avTags"] as? [[String: Any]] ?? [], answerAV: a["avTags"] as? [[String: Any]] ?? [],
            counts: "新規 \(queue["newCount"] as? Int ?? 0) · 学習 \(queue["learningCount"] as? Int ?? 0) · 復習 \(queue["reviewCount"] as? Int ?? 0)")
    }
    func answer(_ card: StudyCard, rating: Int, elapsed: TimeInterval) throws {
        let keys = ["again", "hard", "good", "easy"]
        guard keys.indices.contains(rating), let current = card.states["current"], let next = card.states[keys[rating]] else {
            throw EngineError(message: "学習状態を取得できません。")
        }
        _ = try call("SchedulerService.AnswerCard", ["cardId": card.id, "currentState": current,
            "newState": next, "rating": rating, "answeredAtMillis": String(Int64(Date().timeIntervalSince1970 * 1000)),
            "millisecondsTaken": min(card.options.capMilliseconds, max(0, Int(elapsed * 1000)))])
    }
    func undo() throws { _ = try call("CollectionService.Undo") }
    func importPackage(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".apkg")
        try FileManager.default.copyItem(at: url, to: local)
        defer { try? FileManager.default.removeItem(at: local) }
        try start()
        let backups = root.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        _ = try call("CollectionService.CreateBackup", ["backupFolder": backups.path, "force": true, "waitForCompletion": true])
        var options = try call("ImportExportService.GetImportAnkiPackagePresets")
        options["withScheduling"] = true
        options["withDeckConfigs"] = true
        _ = try call("ImportExportService.ImportAnkiPackage", ["packagePath": local.path, "options": options])
    }
    func exportPackage() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AnkiPad-\(UUID().uuidString).apkg")
        _ = try call("ImportExportService.ExportAnkiPackage", ["outPath": url.path,
            "options": ["withScheduling": true, "withDeckConfigs": true, "withMedia": true],
            "limit": ["wholeCollection": [:]]])
        return url
    }
    func login(username: String, password: String, endpoint: String?) async throws -> SyncCredentials {
        var request: [String: Any] = ["username": username, "password": password]
        if let endpoint, !endpoint.isEmpty { request["endpoint"] = endpoint }
        let auth = try await longCall("SyncService.SyncLogin", request)
        guard let key = auth["hkey"] as? String, !key.isEmpty else { throw EngineError(message: "ログイン情報を取得できませんでした。") }
        return SyncCredentials(username: username, hkey: key, endpoint: auth["endpoint"] as? String)
    }
    func sync(_ credentials: SyncCredentials, syncMedia: Bool = true) async throws -> SyncDecision {
        try backup(force: false)
        let result = try await longCall("SyncService.SyncCollection", ["auth": credentials.request, "syncMedia": syncMedia])
        var cardCount = 0
        var deckCount = 0
        if ["FULL_SYNC", "FULL_DOWNLOAD", "FULL_UPLOAD"].contains(result["required"] as? String ?? "") {
            // Protobuf omits an empty repeated field; a successful empty search
            // therefore has no `ids` key. Backend errors still propagate.
            let ids = try call("SearchService.SearchCards", ["search": ""])["ids"] as? [String] ?? []
            let entries = try call("DecksService.GetDeckNames", ["includeFiltered": true])["entries"] as? [[String: Any]] ?? []
            cardCount = ids.count
            deckCount = entries.count
        }
        return SyncDecision(response: result, localCardCount: cardCount, localDeckCount: deckCount)
    }
    /// Omitting `serverUsn` makes the engine skip media, as upstream does when media fetching is off.
    func fullSync(_ credentials: SyncCredentials, upload: Bool, serverUSN: Int, syncMedia: Bool = true) async throws {
        if upload {
            let ids = try call("SearchService.SearchCards", ["search": ""])["ids"] as? [String] ?? []
            guard !ids.isEmpty else { throw EngineError(message: "空のコレクションはAnkiWebにアップロードできません。ダウンロードで同期してください。") }
        }
        try backup()
        var request: [String: Any] = ["auth": credentials.request, "upload": upload]
        if syncMedia { request["serverUsn"] = serverUSN }
        _ = try await longCall("SyncService.FullUploadOrDownload", request)
    }
    /// Upstream `modSchema(check = false)`: the next sync must replace one side completely.
    func forceOneWaySync() throws {
        _ = try call("_droid/force_one_way_sync")
    }
    func mediaSyncStatus() throws -> [String: Any] { try raw("SyncService.MediaSyncStatus") }
    func beginSyncSession() { syncAbortRequested = false }
    func localSyncState() throws -> LocalSyncState {
        let result = try call("_droid/local_sync_status")
        guard let neverSynced = result["neverSynced"] as? Bool, let hasChanges = result["hasChanges"] as? Bool, let modification = result["modification"] as? String else {
            throw EngineError(message: "ローカルの同期状態を確認できませんでした。")
        }
        return LocalSyncState(neverSynced: neverSynced, hasChanges: hasChanges, modification: modification)
    }
    func abortSync() async throws {
        syncAbortRequested = true
        guard transport != nil else { return }
        while true {
            _ = try raw("SyncService.AbortSync")
            _ = try raw("SyncService.AbortMediaSync")
            let mediaActive: Bool
            do { mediaActive = try raw("SyncService.MediaSyncStatus")["active"] as? Bool == true }
            catch let failure as EngineError where failure.kind == 2 { mediaActive = false }
            if activeSyncCall == nil && !mediaActive { return }
            // A detached network call may not have registered its Rust abort
            // handle yet. Keep cancellation latched until it has unwound.
            try await Task.sleep(nanoseconds: 30_000_000)
        }
    }
    func backup(force: Bool = true) throws {
        try start()
        let folder = root.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try raw("CollectionService.CreateBackup", ["backupFolder": folder.path, "force": force, "waitForCompletion": true])
    }

    func exportCollection() throws -> URL {
        try start()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AnkiPad-\(UUID().uuidString).colpkg")
        do { _ = try raw("ImportExportService.ExportCollectionPackage", ["outPath": url.path, "includeMedia": true]) }
        catch { opened = false; try? start(); throw error }
        opened = false
        try start()
        return url
    }
    func restoreCollection(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".colpkg")
        try FileManager.default.copyItem(at: url, to: local)
        defer { try? FileManager.default.removeItem(at: local) }
        try backup()
        _ = try raw("CollectionService.CloseCollection")
        opened = false
        do {
            _ = try raw("ImportExportService.ImportCollectionPackage", ["colPath": root.appendingPathComponent("collection.anki2").path,
                "backupPath": local.path, "mediaFolder": media.path, "mediaDb": root.appendingPathComponent("collection.media.db2").path])
            try start()
        } catch { try? start(); throw error }
    }

}

// Backend uses internal Rust mutexes. A strong reference retains the native handle
// throughout network work; only progress/abort calls run concurrently with it.
final class BackendTransport: @unchecked Sendable {
    private let handle: UnsafeMutableRawPointer
    init() throws {
        var error: UnsafeMutablePointer<CChar>?
        guard let handle = ap_open(&error) else {
            let message = error.map { String(cString: $0) } ?? "学習エンジンを起動できませんでした。"
            if let error { ap_string_free(error) }
            throw EngineError(message: message)
        }
        self.handle = handle
    }
    deinit { ap_close(handle) }
    func call(_ method: String, _ args: [String: Any] = [:]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: args, options: [.sortedKeys])
        let request = String(decoding: data, as: UTF8.self)
        guard let result = method.withCString({ m in request.withCString { ap_call(handle, m, $0) } }) else {
            throw EngineError(message: "エンジンから応答がありません。")
        }
        defer { ap_string_free(result) }
        let envelope = try JSONSerialization.jsonObject(with: Data(String(cString: result).utf8)) as? [String: Any]
        if let error = envelope?["error"] as? String { throw EngineError(message: error, kind: envelope?["errorKind"] as? Int) }
        guard let value = envelope?["ok"] as? [String: Any] else { throw EngineError(message: "エンジンの応答を読み取れません。") }
        return value
    }
}
