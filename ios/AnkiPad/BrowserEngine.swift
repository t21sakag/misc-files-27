import Foundation

struct BrowserColumn: Identifiable {
    let id: String
    let cardLabel: String
    let noteLabel: String
    let sortsCards: Bool
    let sortsNotes: Bool
}
struct BrowserConfiguration {
    var notesMode: Bool
    var columns: [String]
    var sortColumn: String
    var backwards: Bool
    var savedSearches: [String: String]
}
extension Engine {
    func configValue(_ key: String) throws -> Any? {
        do {
            let result = try call("ConfigService.GetConfigJson", ["val": key])
            guard let raw = result["json"] as? String, let data = Data(base64Encoded: raw) else { return nil }
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch let error as EngineError where error.kind == 11 { return nil }
    }
    func setConfigValue(_ key: String, value: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        _ = try call("ConfigService.SetConfigJson", ["key": key, "valueJson": data.base64EncodedString()])
    }
    func browserConfiguration(notesMode: Bool? = nil) throws -> BrowserConfiguration {
        let current = try call("ConfigService.GetConfigBool", ["key": "BROWSER_TABLE_SHOW_NOTES_MODE"])["val"] as? Bool ?? false
        let mode = notesMode ?? current
        if mode != current { _ = try call("ConfigService.SetConfigBool", ["key": "BROWSER_TABLE_SHOW_NOTES_MODE", "value": mode]) }
        let rawColumns = try configValue(mode ? "activeNoteCols" : "activeCols") as? [String] ?? (mode ? ["noteFld", "note", "template", "noteTags"] : ["noteFld", "template", "cardDue", "deck"])
        var seen: Set<String> = []
        let uniqueColumns = rawColumns.filter { seen.insert($0).inserted }
        return BrowserConfiguration(notesMode: mode,
            columns: uniqueColumns.isEmpty ? ["noteFld"] : uniqueColumns,
            sortColumn: try configValue(mode ? "noteSortType" : "sortType") as? String ?? "noteFld",
            backwards: try configValue(mode ? "browserNoteSortBackwards" : "sortBackwards") as? Bool ?? false,
            savedSearches: try configValue("savedFilters") as? [String: String] ?? [:])
    }
    func saveBrowserConfiguration(_ config: BrowserConfiguration) throws {
        try setConfigValue(config.notesMode ? "activeNoteCols" : "activeCols", value: config.columns)
        try setConfigValue(config.notesMode ? "noteSortType" : "sortType", value: config.sortColumn)
        try setConfigValue(config.notesMode ? "browserNoteSortBackwards" : "sortBackwards", value: config.backwards)
        try setConfigValue("savedFilters", value: config.savedSearches)
    }
    func browserColumns() throws -> [BrowserColumn] {
        let result = try call("SearchService.AllBrowserColumns")
        return (result["columns"] as? [[String: Any]] ?? []).compactMap { value in
            guard let key = value["key"] as? String, !key.isEmpty else { return nil }
            return BrowserColumn(id: key, cardLabel: value["cardsModeLabel"] as? String ?? key,
                noteLabel: value["notesModeLabel"] as? String ?? key,
                sortsCards: (value["sortingCards"] as? String ?? "SORTING_NONE") != "SORTING_NONE",
                sortsNotes: (value["sortingNotes"] as? String ?? "SORTING_NONE") != "SORTING_NONE")
        }
    }
    func searchBrowserIDs(_ query: String, config: BrowserConfiguration) throws -> [String] {
        let current = try call("ConfigService.GetConfigBool", ["key": "BROWSER_TABLE_SHOW_NOTES_MODE"])["val"] as? Bool ?? false
        if current != config.notesMode { _ = try call("ConfigService.SetConfigBool", ["key": "BROWSER_TABLE_SHOW_NOTES_MODE", "value": config.notesMode]) }
        return try call(config.notesMode ? "SearchService.SearchNotes" : "SearchService.SearchCards", ["search": query,
            "order": ["builtin": ["column": config.sortColumn, "reverse": config.backwards]]])["ids"] as? [String] ?? []
    }
    func browserRows(_ ids: [String], config: BrowserConfiguration, showMediaFilenames: Bool = false) throws -> [BrowserCard] {
        let current = try call("ConfigService.GetConfigBool", ["key": "BROWSER_TABLE_SHOW_NOTES_MODE"])["val"] as? Bool ?? false
        if current != config.notesMode { _ = try call("ConfigService.SetConfigBool", ["key": "BROWSER_TABLE_SHOW_NOTES_MODE", "value": config.notesMode]) }
        _ = try call("SearchService.SetActiveBrowserColumns", ["vals": config.columns])
        return try ids.map { id in
            let cards: [String]
            let note: [String: Any]
            if config.notesMode {
                cards = try call("NotesService.CardsOfNote", ["nid": id])["cids"] as? [String] ?? []
                note = try call("NotesService.GetNote", ["nid": id])
            } else {
                cards = [id]
                let card = try call("CardsService.GetCard", ["cid": id])
                note = try call("NotesService.GetNote", ["nid": card["noteId"] as? String ?? "0"])
            }
            let card = try cards.first.map { try call("CardsService.GetCard", ["cid": $0]) } ?? [:]
            let fields = note["fields"] as? [String] ?? []
            func plain(_ index: Int) throws -> String {
                guard fields.indices.contains(index) else { return "" }
                let text: String
                if showMediaFilenames { text = fields[index] }
                else { text = try call("CardRenderingService.StripAvTags", ["val": fields[index]])["val"] as? String ?? "" }
                return try call("CardRenderingService.HtmlToTextLine", ["text": text, "preserveMediaFilenames": true])["val"] as? String ?? ""
            }
            let row = try call("SearchService.BrowserRowForId", ["val": id])
            let cells = (row["cells"] as? [[String: Any]] ?? []).map {
                BrowserMediaText.display($0["text"] as? String ?? "", showMediaFilenames: showMediaFilenames)
            }
            return BrowserCard(id: id, noteID: note["id"] as? String ?? "0", front: try plain(0), back: try plain(1), deckID: card["deckId"] as? String ?? "0",
                suspended: (card["queue"] as? Int ?? 0) == -1, flag: (card["flags"] as? Int ?? 0) & 7, cardIDs: cards,
                metadata: Dictionary(zip(config.columns, cells), uniquingKeysWith: { first, _ in first }))
        }
    }
    func cardIDsForNotes(_ ids: [String]) throws -> [String] {
        try ids.flatMap { try call("NotesService.CardsOfNote", ["nid": $0])["cids"] as? [String] ?? [] }
    }
    func noteIDsForCards(_ ids: [String]) throws -> [String] {
        var result: Set<String> = []
        for start in stride(from: 0, to: ids.count, by: 500) {
            let chunk = ids[start..<min(start + 500, ids.count)]
            let notes = try call("SearchService.SearchNotes", ["search": "cid:" + chunk.joined(separator: ",")])["ids"] as? [String] ?? []
            result.formUnion(notes)
        }
        return Array(result)
    }
    func reposition(_ ids: [String], start: Int, step: Int, random: Bool, shift: Bool) throws {
        _ = try call("SchedulerService.SortCards", ["cardIds": ids, "startingFrom": start, "stepSize": step, "randomize": random, "shiftExisting": shift])
    }
}
