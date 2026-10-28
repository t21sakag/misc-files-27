import Foundation
extension Engine {
    func reminderForecast(_ config: ReviewReminderConfiguration, now: Date) throws -> [ReviewReminderForecast] {
        let today = try call("SchedulerService.SchedTimingToday")
        let cutoff = Double(today["nextDayAt"] as? String ?? "") ?? 0
        var search = "rated:1"
        if let id = config.deckID {
            let decks = try call("DecksService.GetDeckNames", ["includeFiltered": true])["entries"] as? [[String: Any]] ?? []
            guard decks.contains(where: { $0["id"] as? String == id }) else {
                return ReviewReminderDates.upcoming(config, now: now).map { ReviewReminderForecast(date: $0, dueCount: nil, reviewed: false) }
            }
            let deck = try call("DecksService.GetDeck", ["did": id])
            let built = try call("SearchService.BuildSearchString", ["group": ["joiner": "AND", "nodes": [["deck": deck["name"] as? String ?? ""], ["parsableText": search]]]])
            search = built["val"] as? String ?? search
        }
        var reviewed = false
        if config.onlyIfNoReviews { reviewed = !(try call("SearchService.SearchCards", ["search": search])["ids"] as? [String] ?? []).isEmpty }
        func find(_ node: [String: Any], id: String) -> [String: Any]? {
            if node["deckId"] as? String == id { return node }
            for child in node["children"] as? [[String: Any]] ?? [] { if let found = find(child, id: id) { return found } }
            return nil
        }
        return try ReviewReminderDates.upcoming(config, now: now).map { date in
            let root = try call("DecksService.DeckTree", ["now": String(Int64(date.timeIntervalSince1970))])
            let node = config.deckID.flatMap { find(root, id: $0) } ?? (config.deckID == nil ? root : nil)
            let count = node.map { node in ["newCount", "learnCount", "reviewCount"].reduce(0) { $0 + (node[$1] as? Int ?? 0) } }
            return ReviewReminderForecast(date: date, dueCount: count, reviewed: date.timeIntervalSince1970 < cutoff && reviewed)
        }
    }
}
