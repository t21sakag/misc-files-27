import Foundation
import UIKit

struct NamedID: Identifiable, Hashable {
    let id: String
    let name: String
}
struct NoteDocument {
    var raw: [String: Any]
    var fieldNames: [String]
    var fields: [String]
    var fieldConfigs: [[String: Any]]
    var tags: String
    var deckID: String
    var originalDeckID: String
    var cardIDsForMove: [String]
    var id: String { raw["id"] as? String ?? "0" }
    var typeID: String { raw["notetypeId"] as? String ?? "0" }
}
struct BrowserCard: Identifiable {
    let id: String
    let noteID: String
    let front: String
    let back: String
    let deckID: String
    let suspended: Bool
    let flag: Int
    let cardIDs: [String]
    let metadata: [String: String]
}
struct EditorRequest: Identifiable {
    let id = UUID()
    var cardID: String?
    var noteID: String?
    var isNew: Bool { cardID == nil && noteID == nil }
    var deckID: String = "0"
    var copiedDocument: NoteDocument?
    var initialDraft: IncomingNoteDraft?
    var incomingMedia: IncomingImportFile?
    var sharedReceipt: SharedInboxReceipt?
}

extension Engine {
    func noteTypes() throws -> [NamedID] {
        let result = try call("NotetypesService.GetNotetypeNames")
        return (result["entries"] as? [[String: Any]] ?? []).compactMap { value in
            guard let id = value["id"] as? String, let name = value["name"] as? String else { return nil }
            return NamedID(id: id, name: name)
        }
    }
    func noteDocument(cardID: String?, noteID: String? = nil, typeID: String?, deckID: String) throws -> NoteDocument {
        let defaults = try call("NotesService.DefaultsForAdding", ["homeDeckOfCurrentReviewCard": deckID == "0" ? "0" : deckID])
        var targetDeck = deckID == "0" ? defaults["deckId"] as? String ?? "1" : deckID
        let note: [String: Any]
        if let noteID {
            note = try call("NotesService.GetNote", ["nid": noteID])
        } else if let cardID {
            let card = try call("CardsService.GetCard", ["cid": cardID])
            targetDeck = card["deckId"] as? String ?? deckID
            note = try call("NotesService.GetNote", ["nid": card["noteId"] as? String ?? "0"])
        } else {
            guard let chosen = try typeID ?? defaults["notetypeId"] as? String ?? noteTypes().first?.id else { throw EngineError(message: AppText.localized("ノートタイプがありません。")) }
            note = try call("NotesService.NewNote", ["ntid": chosen])
        }
        let type = try call("NotetypesService.GetNotetype", ["ntid": note["notetypeId"] as? String ?? "0"])
        var fields = note["fields"] as? [String] ?? []
        let definitions = type["fields"] as? [[String: Any]] ?? []
        let names = definitions.map { $0["name"] as? String ?? AppText.localized("フィールド") }
        let configs = definitions.map { $0["config"] as? [String: Any] ?? [:] }
        if cardID == nil && noteID == nil {
            let kept = stickyFieldValues[note["notetypeId"] as? String ?? "0"] ?? [:]
            for index in fields.indices where names.indices.contains(index) && configs.indices.contains(index) {
                if configs[index]["sticky"] as? Bool == true { fields[index] = kept[names[index]] ?? "" }
            }
        }
        return NoteDocument(raw: note, fieldNames: names, fields: fields, fieldConfigs: configs,
            tags: (note["tags"] as? [String] ?? []).joined(separator: " "), deckID: targetDeck, originalDeckID: targetDeck,
            cardIDsForMove: cardID.map { [$0] } ?? [])
    }
    func saveNote(_ document: NoteDocument, isNew: Bool) throws {
        var note = document.raw
        note["fields"] = document.fields
        note["tags"] = document.tags.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if isNew {
            _ = try call("NotesService.AddNote", ["note": note, "deckId": document.deckID])
            var kept: [String: String] = [:]
            for index in document.fields.indices where document.fieldConfigs.indices.contains(index) && document.fieldNames.indices.contains(index) {
                if document.fieldConfigs[index]["sticky"] as? Bool == true { kept[document.fieldNames[index]] = document.fields[index] }
            }
            stickyFieldValues[document.typeID] = kept
        } else {
            _ = try call("NotesService.UpdateNotes", ["notes": [note]])
            if document.deckID != document.originalDeckID {
                let cards = document.cardIDsForMove.isEmpty ? try call("NotesService.CardsOfNote", ["nid": document.id])["cids"] as? [String] ?? [] : document.cardIDsForMove
                _ = try call("CardsService.SetDeck", ["cardIds": cards, "deckId": document.deckID])
            }
        }
    }
    func checkNoteDocument(_ document: NoteDocument) throws -> String {
        var note = document.raw
        note["fields"] = document.fields
        return try call("NotesService.NoteFieldsCheck", note)["state"] as? String ?? "NORMAL"
    }
    func searchCardIDs(_ query: String) throws -> [String] {
        let response = try call("SearchService.SearchCards", ["search": query, "order": ["builtin": ["column": "noteFld", "reverse": false]]])
        return response["ids"] as? [String] ?? []
    }
    func browserCards(_ ids: [String]) throws -> [BrowserCard] {
        try ids.map { id in
            let card = try call("CardsService.GetCard", ["cid": id])
            let nid = card["noteId"] as? String ?? "0"
            let note = try call("NotesService.GetNote", ["nid": nid])
            let fields = note["fields"] as? [String] ?? []
            func plain(_ index: Int) throws -> String {
                guard fields.indices.contains(index) else { return "" }
                return try call("CardRenderingService.StripHtml", ["text": fields[index], "mode": "PRESERVE_MEDIA_FILENAMES"])["val"] as? String ?? ""
            }
            return BrowserCard(id: id, noteID: nid, front: try plain(0), back: try plain(1), deckID: card["deckId"] as? String ?? "1",
                suspended: (card["queue"] as? Int ?? 0) == -1, flag: (card["flags"] as? Int ?? 0) & 7, cardIDs: [id], metadata: [:])
        }
    }
    func setFlag(_ ids: [String], flag: Int) throws { _ = try call("CardsService.SetFlag", ["cardIds": ids, "flag": flag]) }
    func suspend(_ ids: [String]) throws { _ = try call("SchedulerService.BuryOrSuspendCards", ["cardIds": ids, "mode": "SUSPEND"]) }
    func bury(_ ids: [String], note: Bool = false) throws {
        _ = try call("SchedulerService.BuryOrSuspendCards", [note ? "noteIds" : "cardIds": ids, "mode": "BURY_USER"])
    }
    func restoreCards(_ ids: [String]) throws { _ = try call("SchedulerService.RestoreBuriedAndSuspendedCards", ["cids": ids]) }
    func removeNotes(_ ids: [String]) throws { _ = try call("NotesService.RemoveNotes", ["noteIds": ids]) }
    func removeCards(_ ids: [String]) throws { _ = try call("CardsService.RemoveCards", ["cardIds": ids]) }
    func moveCards(_ ids: [String], deck: String) throws { _ = try call("CardsService.SetDeck", ["cardIds": ids, "deckId": deck]) }
    func setDue(_ ids: [String], days: String) throws { _ = try call("SchedulerService.SetDueDate", ["cardIds": ids, "days": days]) }
    func forget(_ ids: [String]) throws { _ = try call("SchedulerService.ScheduleCardsAsNew", ["cardIds": ids, "log": true, "resetCounts": false, "restorePosition": true]) }
    func tagNotes(_ ids: [String], tags: String, remove: Bool) throws {
        _ = try call(remove ? "TagsService.RemoveNoteTags" : "TagsService.AddNoteTags", ["noteIds": ids, "tags": tags])
    }
    func createDeck(_ name: String) throws {
        var deck = try call("DecksService.NewDeck")
        deck["name"] = name
        _ = try call("DecksService.AddDeck", deck)
    }
    func renameDeck(_ id: String, name: String) throws { _ = try call("DecksService.RenameDeck", ["deckId": id, "newName": name]) }
    func removeDeck(_ id: String) throws { _ = try call("DecksService.RemoveDecks", ["dids": [id]]) }
    func addMedia(_ url: URL) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let preferences = try call("ConfigService.GetPreferences")
        let editing = preferences["editing"] as? [String: Any] ?? [:]
        if editing["pasteImagesAsPng"] as? Bool == true, MediaImagePreparation.canRasterize(url),
           let image = UIImage(contentsOfFile: url.path), let data = image.pngData() {
            let name = url.deletingPathExtension().lastPathComponent + ".png"
            return try call("MediaService.AddMediaFile", ["desiredName": name, "data": data.base64EncodedString()])["val"] as? String ?? name
        }
        guard let filename = try call("MediaService.AddMediaFromPath", ["path": url.path])["val"] as? String else { throw EngineError(message: AppText.localized("メディアを読み込めませんでした。")) }
        return filename
    }
    func webProtobuf(_ method: String, input: String) throws -> String {
        guard !method.contains("sync"), !method.contains("login"), !method.contains("certificate"),
              method.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression) != nil else {
            throw EngineError(message: AppText.localized("この画面から呼び出せない操作です。"))
        }
        return try call("_anki/" + method, ["data": input])["data"] as? String ?? ""
    }
    func cardStatistics(_ id: String) throws -> [String: Any] { try call("StatsService.CardStats", ["cid": id]) }
}
