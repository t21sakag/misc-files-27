import SwiftUI

struct CardPreviewRequest: Identifiable {
    let id = UUID()
    let ids: [String]
}
struct PreviewCard {
    let mutationKey = UUID()
    let id: String
    let deckID: String
    let noteID: String
    let ordinal: Int
    var flag: Int
    var marked: Bool
    let rendering: TemplatePreview
    let typing: TypedAnswerSpec?
    let options: ReviewOptions
}
extension Engine {
    func togglePreviewMark(_ noteID: String) throws -> Bool {
        let note = try call("NotesService.GetNote", ["nid": noteID])
        let marked = (note["tags"] as? [String] ?? []).contains { $0.lowercased() == "marked" }
        try tagNotes([noteID], tags: "marked", remove: marked)
        return !marked
    }
    func previewCard(_ id: String) throws -> PreviewCard {
        let card = try call("CardsService.GetCard", ["cid": id])
        let note = try call("NotesService.GetNote", ["nid": card["noteId"] as? String ?? "0"])
        let ordinal = card["templateIdx"] as? Int ?? 0
        let rendered = try call("CardRenderingService.RenderExistingCard", ["cardId": id, "partialRender": true])
        func html(_ key: String, front: String = "") throws -> String {
            try (rendered[key] as? [[String: Any]] ?? []).map { node in
                if let text = node["text"] as? String { return text }
                if let replacement = node["replacement"] as? [String: Any], replacement["fieldName"] as? String == "FrontSide" { return front }
                throw EngineError(message: "未対応のテンプレートフィルターです。")
            }.joined()
        }
        let question = try call("CardRenderingService.ExtractAvTags", ["text": try html("questionNodes"), "questionSide": true])
        let answer = try call("CardRenderingService.ExtractAvTags", ["text": try html("answerNodes", front: question["text"] as? String ?? ""), "questionSide": false])
        let rendering = TemplatePreview(question: question["text"] as? String ?? "", answer: answer["text"] as? String ?? "",
            css: rendered["css"] as? String ?? "", questionAV: question["avTags"] as? [[String: Any]] ?? [], answerAV: answer["avTags"] as? [[String: Any]] ?? [])
        return PreviewCard(id: id, deckID: card["deckId"] as? String ?? "1", noteID: card["noteId"] as? String ?? "0", ordinal: ordinal, flag: (card["flags"] as? Int ?? 0) & 7, marked: (note["tags"] as? [String] ?? []).contains { $0.lowercased() == "marked" }, rendering: rendering,
            typing: try typingSpec(question: rendering.question, noteID: card["noteId"] as? String ?? "0", ordinal: ordinal), options: try reviewOptions(card: card))
    }
    func comparePreview(_ card: PreviewCard, provided: String) throws -> String {
        guard let spec = card.typing else { return card.rendering.answer }
        let diff = try call("CardRenderingService.CompareAnswer", ["expected": spec.expected, "provided": provided, "combining": spec.combining])["val"] as? String ?? ""
        return TypedAnswerMarkup.replace(in: card.rendering.answer, with: diff)
    }
}

struct CardPreviewView: View {
    @ObservedObject var model: StudyModel
    let request: CardPreviewRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var index = 0
    @State private var card: PreviewCard?
    @State private var answer = false
    @State private var answerOnly = false
    @State private var answerHTML: String?
    @State private var typed = ""
    @State private var busy = false
    @State private var error: String?
    @State private var editor: EditorRequest?
    @State private var revision = 0
    @State private var audio = CardAudio()
    @State private var visible = true
    @State private var speech = CardScriptSpeech()
    @State private var recognition = CardScriptRecognition()
    @State private var scriptEvents: [CardScriptEvent] = []
    @State private var loadGeneration = UUID()
    var body: some View {
        NavigationStack {
            VStack {
                if let card {
                    ReviewerWebView(html: answer ? answerHTML ?? card.rendering.answer : card.rendering.question, css: card.rendering.css,
                        cardID: card.id, ordinal: card.ordinal, typing: card.typing, hideAudioButtons: card.options.hideAudioButtons,
                        typedAnswer: $typed, answer: answer, media: model.engine.media,
                        playTag: { isAnswer, offset in
                            let tags = isAnswer ? card.rendering.answerAV : card.rendering.questionAV
                            if tags.indices.contains(offset) { audio.play([tags[offset]], media: model.engine.media) }
                        }, reveal: reveal, scheduling: nil,
                        schedulingRequest: { _, _ in throw EngineError(message: "プレビューではスケジュールを変更できません。") }, schedulingError: { _ in },
                        cardAPI: { try await previewAPI($0, request: $1, current: card) },
                        scriptEventScope: card.mutationKey.uuidString, cardScriptEvents: scriptEvents,
                        scriptEventDelivered: { id in scriptEvents.removeAll { $0.id == id } },
                        scriptEventError: { error = $0 })
                    HStack {
                        Button { move(-1) } label: { Image(systemName: "chevron.left") }.disabled(index == 0 || busy).keyboardShortcut(.leftArrow, modifiers: [])
                        Spacer()
                        Button(answer ? "表面を表示" : "解答を表示") { if answer { answer = false } else { reveal() } }.disabled(busy)
                        Spacer()
                        Button { move(1) } label: { Image(systemName: "chevron.right") }.disabled(index + 1 >= request.ids.count || busy).keyboardShortcut(.rightArrow, modifiers: [])
                    }.padding()
                } else if let error { ContentUnavailableView("カードを表示できませんでした", systemImage: "exclamationmark.triangle", description: Text(error)) }
                else if request.ids.isEmpty { ContentUnavailableView("カードがありません", systemImage: "rectangle.stack") }
                else { ProgressView() }
            }
            .navigationTitle("プレビュー \(request.ids.isEmpty ? 0 : index + 1) / \(request.ids.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { visible = false; loadGeneration = UUID(); stopScriptAudio(); audio.stop(); dismiss() }.accessibilityIdentifier("preview-close") }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { if let card { editor = EditorRequest(cardID: card.id, deckID: card.deckID) } } label: { Image(systemName: "pencil") }.disabled(card == nil || busy).keyboardShortcut("e", modifiers: [])
                    Button(card?.marked == true ? "マークを外す" : "マークを付ける", systemImage: card?.marked == true ? "star.fill" : "star") {
                        toggleMark()
                    }.disabled(card == nil || busy).keyboardShortcut("*", modifiers: []).accessibilityIdentifier("preview-mark")
                    Button("音声を再生", systemImage: "speaker.wave.2") { replay() }.disabled(card == nil || busy).accessibilityIdentifier("preview-replay").keyboardShortcut("r", modifiers: [])
                    Menu((card?.flag ?? 0) == 0 ? "フラグなし" : "フラグ \(card?.flag ?? 0)", systemImage: "flag") {
                        ForEach(0..<8, id: \.self) { flag in
                            Button { setFlag(flag) } label: {
                                if card?.flag == flag { Label(flag == 0 ? "なし" : "フラグ \(flag)", systemImage: "checkmark") }
                                else { Text(flag == 0 ? "なし" : "フラグ \(flag)") }
                            }.keyboardShortcut(flag == 0 ? nil : KeyboardShortcut(KeyEquivalent(Character(String(flag))), modifiers: .control))
                            .accessibilityIdentifier("preview-flag-\(flag)").accessibilityValue(card?.flag == flag ? "選択中" : "未選択")
                        }
                    }.disabled(card == nil || busy).accessibilityIdentifier("preview-flags")
                    Toggle("裏面のみ", isOn: $answerOnly).disabled(card == nil || busy).keyboardShortcut("b", modifiers: []).onChange(of: answerOnly) { _, next in if next { reveal() } else { answer = false } }
                }
            }
            .sheet(item: $editor, onDismiss: { revision += 1 }) { NoteEditorView(model: model, request: $0) }
            .task(id: "\(index)-\(revision)") { await load() }
            .onAppear { visible = true }
            .onDisappear { visible = false; stopScriptAudio(); audio.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { stopScriptAudio(); audio.stop() }
            }
            .onChange(of: editor?.id) { _, id in
                if id != nil { stopScriptAudio(); audio.stop() }
            }
            .alert("処理できませんでした", isPresented: Binding(get: { error != nil && card != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private func previewAPI(_ endpoint: String, request: [String: Any], current: PreviewCard) async throws -> String {
        func result(_ value: Any, success: Bool = true) throws -> String {
            String(data: try JSONSerialization.data(withJSONObject: ["success": success, "value": value]), encoding: .utf8)!
        }
        guard visible, self.request.ids.indices.contains(index), self.request.ids[index] == current.id, card?.mutationKey == current.mutationKey else {
            return try result("Card is no longer active", success: false)
        }
        let version = request["version"] as? String ?? ""
        guard !(request["developer"] as? String ?? "").isEmpty,
              version.range(of: #"^0\.0\.3(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z"#, options: .regularExpression) != nil else {
            return try result(-1, success: false)
        }
        // Capture this collection before any suspension; never route a preview to
        // the reviewer's current card, which can belong to a different note.
        let engine = model.engine
        let parameter = request["data"] as? String ?? (request["data"].map { String(describing: $0) } ?? "")
        switch endpoint {
        case "init", "enableHorizontalScrollbar", "enableVerticalScrollbar": return try result(true)
        case "isDisplayingAnswer": return try result(answer)
        case "isInFullscreen": return try result(false)
        case "isTopbarShown": return try result(true)
        case "isInNightMode": return try result(request["__nativeNightMode"] as? Bool ?? false)
        case "isActiveNetworkMetered": return try result(await model.networkMetering.isMetered())
        case "eta": return try result(try await engine.ankiDroidETA())
        case "ttsFieldModifierIsAvailable": return try result(false)
        case "ttsIsSpeaking": return try result(speech.isSpeaking)
        case "ttsStop": return try result(speech.stop())
        case "ttsSetLanguage": return try result(speech.setLanguage(parameter))
        case "ttsSetPitch": return try result(speech.setPitch(Float(parameter) ?? .nan))
        case "ttsSetSpeechRate": return try result(speech.setRate(Float(parameter) ?? .nan))
        case "ttsSpeak":
            guard editor == nil, scenePhase == .active,
                  let data = parameter.data(using: .utf8),
                  let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = payload["text"] as? String else { return try result(-1) }
            recognition.cancel()
            return try result(speech.speak(text, queueMode: payload["queueMode"] as? Int ?? 0))
        case "sttSetLanguage": return try result(recognition.setLanguage(parameter))
        case "sttStop": return try result(recognition.finish())
        case "sttStart":
            guard !busy, editor == nil, scenePhase == .active else { return try result(false) }
            audio.stop(); speech.stop()
            let started = await recognition.start { matches, message in
                guard visible, card?.mutationKey == current.mutationKey else { return }
                do {
                    let value: String
                    if let matches { value = String(data: try JSONSerialization.data(withJSONObject: matches), encoding: .utf8)! }
                    else { value = message ?? "Unknown speech recognition error" }
                    scriptEvents.append(CardScriptEvent(mutationKey: current.mutationKey.uuidString,
                        json: try result(value, success: matches != nil)))
                } catch { self.error = error.localizedDescription }
            }
            return try result(started)
        case "showAnswer":
            guard !busy, editor == nil else { return try result(false) }
            reveal()
            return try result(true)
        case "searchCardWithCallback":
            guard UserDefaults.standard.bool(forKey: model.profilePreferenceKey("allowCollectionCardAPI")) else { return try result(false) }
            do {
                let found = try await engine.ankiDroidSearchResults(parameter)
                guard visible, card?.mutationKey == current.mutationKey else { return try result(false) }
                let json = String(data: try JSONSerialization.data(withJSONObject: found), encoding: .utf8)!
                scriptEvents.append(CardScriptEvent(mutationKey: current.mutationKey.uuidString, json: json, kind: .search))
                return try result(true)
            } catch { return try result(false) }
        case "markCard", "setNoteTags", "addTagToNote":
            guard !busy, editor == nil else { return try result(false) }
            busy = true
            defer { busy = false }
            if endpoint == "markCard" {
                let marked = try await engine.togglePreviewMark(current.noteID)
                if card?.mutationKey == current.mutationKey { card?.marked = marked }
            } else {
                guard let data = parameter.data(using: .utf8),
                      let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return try result(false) }
                if endpoint == "addTagToNote" {
                    let noteID = payload["noteId"].map { String(describing: $0) } ?? ""
                    guard let numericID = Int64(noteID), numericID > 0, let tag = payload["tag"] as? String else { return try result(false) }
                    if noteID != current.noteID && !UserDefaults.standard.bool(forKey: model.profilePreferenceKey("allowCollectionCardAPI")) {
                        return try result(false)
                    }
                    try await engine.tagNotes([noteID], tags: tag, remove: false)
                } else {
                    guard let tags = payload["tags"] as? [String] else { return try result(false) }
                    let cleaned = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    guard !cleaned.contains(where: { $0.contains(where: \.isWhitespace) }) else { return try result(false) }
                    var note = try await engine.call("NotesService.GetNote", ["nid": current.noteID])
                    note["tags"] = cleaned
                    _ = try await engine.call("NotesService.UpdateNotes", ["notes": [note]])
                }
            }
            if endpoint != "markCard", card?.mutationKey == current.mutationKey {
                let note = try await engine.call("NotesService.GetNote", ["nid": current.noteID])
                if card?.mutationKey == current.mutationKey {
                    card?.marked = (note["tags"] as? [String] ?? []).contains { $0.lowercased() == "marked" }
                }
            }
            return try result(true)
        case "toggleFlag":
            guard !busy, editor == nil else { return try result(false) }
            let names = ["none", "red", "orange", "green", "blue", "pink", "turquoise", "purple"]
            guard let desired = names.firstIndex(of: request["data"] as? String ?? "") else { return try result(false) }
            let value = current.flag == desired ? 0 : desired
            busy = true
            defer { busy = false }
            try await engine.setFlag([current.id], flag: value)
            if card?.mutationKey == current.mutationKey { card?.flag = value }
            return try result(true)
        default:
            let metadata = try await engine.ankiDroidCardMetadata(current.id)
            guard visible, card?.mutationKey == current.mutationKey else { return try result("Card is no longer active", success: false) }
            guard let value = metadata[endpoint] else {
                return try result("This AnkiDroid API endpoint is not yet available in preview: " + endpoint, success: false)
            }
            return try result(value)
        }
    }
    private func stopScriptAudio() {
        recognition.cancel()
        speech.stop()
        scriptEvents.removeAll()
    }
    private func replay() {
        guard visible, let card, !busy, editor == nil else { return }
        recognition.cancel(); speech.stop()
        let tags = answer ? (card.options.replayQuestion ? card.rendering.questionAV : []) + card.rendering.answerAV : card.rendering.questionAV
        audio.play(tags, media: model.engine.media)
    }
    private func toggleMark() {
        guard visible, let current = card, !busy, editor == nil else { return }
        let engine = model.engine
        busy = true
        Task {
            defer { busy = false }
            do {
                let marked = try await engine.togglePreviewMark(current.noteID)
                if card?.mutationKey == current.mutationKey { card?.marked = marked }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func setFlag(_ desired: Int) {
        guard visible, let current = card, !busy, editor == nil else { return }
        let value = current.flag == desired ? 0 : desired
        let engine = model.engine
        busy = true
        Task {
            defer { busy = false }
            do {
                try await engine.setFlag([current.id], flag: value)
                if card?.mutationKey == current.mutationKey { card?.flag = value }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func move(_ offset: Int) {
        guard visible, !busy, request.ids.indices.contains(index + offset) else { return }
        stopScriptAudio(); audio.stop()
        card = nil
        busy = true
        index += offset
    }
    private func load() async {
        guard request.ids.indices.contains(index) else { return }
        let generation = UUID()
        loadGeneration = generation
        let target = request.ids[index]
        let engine = model.engine
        busy = true
        stopScriptAudio()
        card = nil; error = nil; typed = ""; answer = false; answerHTML = nil; audio.stop()
        defer { if loadGeneration == generation { busy = false } }
        do {
            let loaded = try await engine.previewCard(target)
            try Task.checkCancellation()
            guard visible, loadGeneration == generation else { return }
            card = loaded
            if answerOnly {
                let compared = try await engine.comparePreview(loaded, provided: "")
                try Task.checkCancellation()
                guard visible, loadGeneration == generation else { return }
                answerHTML = compared
                answer = true
                if loaded.options.autoplay { audio.play(loaded.rendering.answerAV, media: model.engine.media) }
            } else if loaded.options.autoplay { audio.play(loaded.rendering.questionAV, media: model.engine.media) }
        } catch is CancellationError {} catch {
            if visible, loadGeneration == generation { self.error = error.localizedDescription }
        }
    }
    private func reveal() {
        guard visible, let card, !busy, editor == nil else { return }
        let engine = model.engine
        let provided = typed
        busy = true
        Task {
            defer { busy = false }
            do {
                let compared = try await engine.comparePreview(card, provided: provided)
                guard visible, self.card?.mutationKey == card.mutationKey else { return }
                answerHTML = compared
                answer = true
                if card.options.interruptAudio { audio.stop() }
                if card.options.autoplay { audio.append(card.rendering.answerAV, media: model.engine.media) }
            } catch { self.error = error.localizedDescription }
        }
    }
}
