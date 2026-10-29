import Foundation
import UIKit

extension Engine {
    func ankiDroidSearchResults(_ search: String) throws -> [[String: Any]] {
        let column = try configValue("sortType") as? String ?? "noteFld"
        let reverse = try configValue("sortBackwards") as? Bool ?? false
        let ids = try call("SearchService.SearchCards", ["search": search, "order": ["builtin": ["column": column, "reverse": reverse]]])["ids"] as? [String] ?? []
        var notes: [String: [String: Any]] = [:]
        var types: [String: [String]] = [:]
        return try ids.map { id in
            let card = try call("CardsService.GetCard", ["cid": id])
            guard let nid = card["noteId"] as? String, let cardNumber = Int64(id), let noteNumber = Int64(nid) else { throw EngineError(message: AppText.localized("カードIDを読み取れませんでした。")) }
            let note: [String: Any]
            if let cached = notes[nid] { note = cached } else { note = try call("NotesService.GetNote", ["nid": nid]); notes[nid] = note }
            let typeID = note["notetypeId"] as? String ?? "0"
            let names: [String]
            if let cached = types[typeID] { names = cached } else {
                names = (try noteType(typeID)["fields"] as? [[String: Any]] ?? []).map { $0["name"] as? String ?? "" }
                types[typeID] = names
            }
            var fields: [String: String] = [:]
            for (name, value) in zip(names, note["fields"] as? [String] ?? []) { fields[name] = value }
            return ["cardId": cardNumber, "noteId": noteNumber, "fieldsData": fields]
        }
    }
    func ankiDroidETA() throws -> Int {
        let timing = try call("SchedulerService.SchedTimingToday")
        guard let rawCutoff = timing["nextDayAt"] as? String, let cutoff = Int64(rawCutoff) else { throw EngineError(message: AppText.localized("日付の境界を取得できませんでした。")) }
        let queue = try call("SchedulerService.GetQueuedCards", ["fetchLimit": 1])
        return try call("_droid/eta", ["cutoffMillis": (cutoff - 10 * 86400) * 1000,
            "new": queue["newCount"] as? Int ?? 0,
            "learning": queue["learningCount"] as? Int ?? 0,
            "review": queue["reviewCount"] as? Int ?? 0])["minutes"] as? Int ?? -1
    }
    func ankiDroidCardMetadata(_ id: String) throws -> [String: Any] {
        let card = try call("CardsService.GetCard", ["cid": id])
        let note = try call("NotesService.GetNote", ["nid": card["noteId"] as? String ?? "0"])
        let deck = try call("DecksService.GetDeck", ["did": card["deckId"] as? String ?? "1"])
        let queue = try call("SchedulerService.GetQueuedCards", ["fetchLimit": 1])
        let mapping = ["cardReps": "reps", "cardInterval": "interval", "cardFactor": "easeFactor", "cardMod": "mtimeSecs", "cardId": "id", "cardNid": "noteId", "cardType": "ctype", "cardDid": "deckId", "cardLeft": "remainingSteps", "cardODid": "originalDeckId", "cardODue": "originalDue", "cardQueue": "queue", "cardLapses": "lapses", "cardDue": "due"]
        var values: [String: Any] = [:]
        for (endpoint, key) in mapping {
            if let string = card[key] as? String, let number = Int64(string) { values[endpoint] = number }
            else { values[endpoint] = card[key] ?? 0 }
        }
        values["cardFlag"] = (card["flags"] as? Int ?? 0) & 7
        values["cardMark"] = (note["tags"] as? [String] ?? []).contains { $0.lowercased() == "marked" }
        values["getNoteTags"] = String(data: try JSONSerialization.data(withJSONObject: note["tags"] as? [String] ?? []), encoding: .utf8)!
        values["deckName"] = (deck["name"] as? String ?? "").components(separatedBy: "::").last ?? ""
        values["newCardCount"] = queue["newCount"] as? Int ?? 0
        values["lrnCardCount"] = queue["learningCount"] as? Int ?? 0
        values["revCardCount"] = queue["reviewCount"] as? Int ?? 0
        return values
    }
}
extension StudyModel {
    private func allowCollectionCardAPI() -> Bool {
        if UserDefaults.standard.bool(forKey: profilePreferenceKey("allowCollectionCardAPI")) { return true }
        if cardAPIDenials < 2 { showCardToast(AppText.localized("カードによる他のノートの読み取り・タグ変更は設定で許可されていません。"), short: false) }
        cardAPIDenials += 1
        return false
    }
    func ankiDroidCardAPI(_ endpoint: String, request: [String: Any], cardID: String, mutationKey: String) async throws -> String {
        func result(_ value: Any, success: Bool = true) throws -> String {
            String(data: try JSONSerialization.data(withJSONObject: ["success": success, "value": value]), encoding: .utf8)!
        }
        let engine = self.engine
        guard let current = card, current.id == cardID, current.mutationKey == mutationKey else { return try result("Card is no longer active", success: false) }
        let version = request["version"] as? String ?? ""
        guard !(request["developer"] as? String ?? "").isEmpty, version.range(of: #"^0\.0\.3(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z"#, options: .regularExpression) != nil else { return try result(-1, success: false) }
        let parameter = request["data"] as? String ?? (request["data"].map { String(describing: $0) } ?? "")
        switch endpoint {
        case "sttSetLanguage": return try result(cardRecognition.setLanguage(parameter))
        case "sttStop": return try result(cardRecognition.finish())
        case "sttStart":
            guard !busy, !reviewingInteractionBlocked else { return try result(false) }
            stopCardAudioForRecognition()
            let key = current.mutationKey
            let started = await cardRecognition.start { [weak self] matches, error in
                guard let self, self.card?.mutationKey == key else { return }
                do {
                    let value: String
                    if let matches { value = String(data: try JSONSerialization.data(withJSONObject: matches), encoding: .utf8)! }
                    else { value = error ?? "Unknown speech recognition error" }
                    let json = try result(value, success: matches != nil)
                    self.cardScriptEvents.append(CardScriptEvent(mutationKey: key, json: json))
                } catch { self.error = error.localizedDescription }
            }
            return try result(started)
        case "ttsFieldModifierIsAvailable": return try result(false)
        case "ttsIsSpeaking": return try result(cardSpeech.isSpeaking)
        case "ttsStop": return try result(cardSpeech.stop())
        case "ttsSetLanguage": return try result(cardSpeech.setLanguage(parameter))
        case "ttsSetPitch": return try result(cardSpeech.setPitch(Float(parameter) ?? .nan))
        case "ttsSetSpeechRate": return try result(cardSpeech.setRate(Float(parameter) ?? .nan))
        case "ttsSpeak":
            guard let data = parameter.data(using: .utf8), let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any], let text = payload["text"] as? String else { return try result(-1) }
            return try result(cardSpeech.speak(text, queueMode: payload["queueMode"] as? Int ?? 0))
        case "showNavigationDrawer", "showOptionsMenu":
            guard !busy, !showingNavigationDrawer, !showingReviewerOptions, !showingSettings, !showingBrowser,
                  !showingAccount, editorRequest == nil, backendPage == nil, cardActionRequest == nil else { return try result(false) }
            if endpoint == "showNavigationDrawer" { showingNavigationDrawer = true }
            else { showingReviewerOptions = true }
            return try result(true)
        case "searchCardWithCallback":
            guard allowCollectionCardAPI() else { return try result(false) }
            do {
                let found = try await engine.ankiDroidSearchResults(parameter)
                let json = String(data: try JSONSerialization.data(withJSONObject: found), encoding: .utf8)!
                if card?.mutationKey == current.mutationKey { cardScriptEvents.append(CardScriptEvent(mutationKey: current.mutationKey, json: json, kind: .search)) }
                return try result(true)
            } catch { return try result(false) }
        case "addTagToCard":
            guard !busy else { return try result(false) }
            cardActionRequest = ReviewCardActionRequest(cardID: current.id, noteID: current.noteID, action: .tags)
            return try result(true)
        case "searchCard":
            guard !busy else { return try result(false) }
            let deck = try await engine.call("DecksService.GetDeck", ["did": selected?.id ?? current.deckID])
            let search = try await engine.call("SearchService.BuildSearchString", ["group": ["joiner": "AND", "nodes": [["deck": deck["name"] as? String ?? ""], ["parsableText": parameter]]]])
            browserSearch = search["val"] as? String ?? ""
            showingBrowser = true
            return try result(true)
        case "showToast":
            guard let data = parameter.data(using: .utf8), let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any], let text = payload["text"] as? String else { return try result(false) }
            showCardToast(text.removingPercentEncoding ?? text, short: payload["shortLength"] as? Bool ?? true)
            return try result(true)
        case "isActiveNetworkMetered": return try result(await networkMetering.isMetered())
        case "eta": return try result(try await engine.ankiDroidETA())
        case "init", "enableHorizontalScrollbar", "enableVerticalScrollbar": return try result(true)
        case "isInFullscreen": return try result(reviewDisplayMode.isFullscreen)
        case "isTopbarShown": return try result(showReviewTopbar)
        case "setFullscreenButtonsAndMenu", "setFullscreenButtonsOnly", "setFullscreenAllGone":
            reviewDisplayMode = endpoint == "setFullscreenButtonsOnly" ? .buttonsOnly : endpoint == "setFullscreenAllGone" ? .allGone : .buttonsAndMenu
            if reviewDisplayMode.isFullscreen { showCardToast(AppText.localized("画面を3回タップすると操作バーを表示できます。"), short: false) }
            return try result(true)
        case "isDisplayingAnswer": return try result(revealed)
        case "isInNightMode":
            if let actual = request["__nativeNightMode"] as? Bool { return try result(actual) }
            let appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system"
            let dark = appearance == "dark" || (appearance == "system" && UITraitCollection.current.userInterfaceStyle == .dark)
            return try result(dark)
        case "nextTime1", "nextTime2", "nextTime3", "nextTime4":
            let index = Int(endpoint.suffix(1))! - 1
            return try result(current.intervals.indices.contains(index) ? current.intervals[index] : "")
        case "showAnswer":
            guard !busy, !reviewingInteractionBlocked, schedulerReady else { return try result(false) }
            reveal(); return try result(true)
        case "answerEase1", "answerEase2", "answerEase3", "answerEase4":
            guard !busy, !reviewingInteractionBlocked, schedulerReady else { return try result(false) }
            if revealed { answer(Int(endpoint.suffix(1))! - 1) } else { reveal() }
            return try result(true)
        case "markCard", "toggleFlag", "setNoteTags", "addTagToNote", "buryCard", "buryNote", "suspendCard", "suspendNote", "setCardDue", "resetProgress":
            guard !busy else { return try result(false) }
            busy = true
            defer { busy = false }
            switch endpoint {
            case "markCard":
                try await engine.tagNotes([current.noteID], tags: "marked", remove: current.marked)
                if card?.id == current.id { card?.marked = !current.marked }
            case "toggleFlag":
                let names = ["none", "red", "orange", "green", "blue", "pink", "turquoise", "purple"]
                guard let desired = names.firstIndex(of: parameter) else { return try result(false) }
                let flag = current.flag == desired ? 0 : desired
                try await engine.setFlag([current.id], flag: flag)
                if card?.id == current.id { card?.flag = flag }
            case "setNoteTags", "addTagToNote":
                guard let data = parameter.data(using: .utf8), let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return try result(false) }
                if endpoint == "addTagToNote" {
                    let noteID = payload["noteId"].map { String(describing: $0) } ?? ""
                    guard let tag = payload["tag"] as? String else { return try result(false) }
                    if noteID != current.noteID && !allowCollectionCardAPI() { return try result(false) }
                    try await engine.tagNotes([noteID], tags: tag, remove: false)
                    if noteID == current.noteID, card?.id == current.id {
                        let updated = try await engine.call("NotesService.GetNote", ["nid": noteID])
                        card?.marked = (updated["tags"] as? [String] ?? []).contains { $0.lowercased() == "marked" }
                    }
                } else {
                    guard let tags = payload["tags"] as? [String] else { return try result(false) }
                    let cleaned = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    guard !cleaned.contains(where: { $0.contains(where: \.isWhitespace) }) else { return try result(false) }
                    var note = try await engine.call("NotesService.GetNote", ["nid": current.noteID])
                    note["tags"] = cleaned
                    _ = try await engine.call("NotesService.UpdateNotes", ["notes": [note]])
                    if card?.id == current.id { card?.marked = cleaned.contains { $0.lowercased() == "marked" } }
                }
            case "buryCard", "buryNote", "suspendCard", "suspendNote":
                let note = endpoint.hasSuffix("Note")
                _ = try await engine.call("SchedulerService.BuryOrSuspendCards", [note ? "noteIds" : "cardIds": [note ? current.noteID : current.id], "mode": endpoint.hasPrefix("suspend") ? "SUSPEND" : "BURY_USER"])
                try await reloadAfterCardAPIMutation()
            case "setCardDue":
                guard let days = Int(parameter), (0...9999).contains(days) else { return try result(false) }
                try await engine.backup()
                try await engine.setDue([current.id], days: "\(days)-\(days)!")
                try await reloadAfterCardAPIMutation()
            case "resetProgress":
                try await engine.backup()
                _ = try await engine.call("SchedulerService.ScheduleCardsAsNew", ["cardIds": [current.id], "log": true, "restorePosition": false, "resetCounts": false, "context": "REVIEWER"])
                try await reloadAfterCardAPIMutation()
            default: break
            }
            return try result(true)
        default:
            let metadata = try await engine.ankiDroidCardMetadata(current.id)
            guard let value = metadata[endpoint] else { return try result("AnkiPad has not implemented this AnkiDroid API endpoint: " + endpoint, success: false) }
            return try result(value)
        }
    }
}


extension StudyModel {
    func performTemplateAction(_ number: Int) {
        guard (1...9).contains(number), !busy, !reviewingInteractionBlocked, let card else { return }
        cardScriptEvents.append(CardScriptEvent(mutationKey: card.mutationKey, json: String(number), kind: .userAction))
    }
    func showTemplateHint(all: Bool) {
        guard !busy, !reviewingInteractionBlocked, let card else { return }
        cardScriptEvents.append(CardScriptEvent(mutationKey: card.mutationKey, json: all ? "all" : "next", kind: .hint))
    }
}
