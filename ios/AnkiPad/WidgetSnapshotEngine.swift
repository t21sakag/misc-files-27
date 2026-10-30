import Foundation

extension Engine {
    /// One actor turn observes the scheduler without selecting a deck or
    /// fetching a card. Root counts already include children and deck limits.
    func widgetSnapshot(now: Date = Date()) throws -> WidgetCollectionSnapshot {
        let timing = try call("SchedulerService.SchedTimingToday")
        guard let raw = timing["nextDayAt"] as? String, let cutoff = TimeInterval(raw), cutoff > now.timeIntervalSince1970 else {
            throw EngineError(message: AppText.localized("日付の境界を取得できませんでした。"))
        }
        let tree = try call("DecksService.DeckTree", ["now": String(Int64(now.timeIntervalSince1970))])
        func counts(_ node: [String: Any]) -> WidgetCounts {
            WidgetCounts(new: node["newCount"] as? Int ?? 0, learning: node["learnCount"] as? Int ?? 0, review: node["reviewCount"] as? Int ?? 0)
        }
        let total = counts(tree)
        let minutes = try call("_droid/eta", ["cutoffMillis": Int64((cutoff - 10 * 86400) * 1000),
            "new": total.new, "learning": total.learning, "review": total.review])["minutes"] as? Int ?? -1
        let decks = Deck.flatten(tree["children"] as? [[String: Any]] ?? []).map {
            WidgetDeckSnapshot(id: $0.id, name: $0.name, counts: WidgetCounts(new: $0.newCount, learning: $0.learnCount, review: $0.reviewCount))
        }
        let current = try call("DecksService.GetCurrentDeck")["id"] as? String
        return WidgetCollectionSnapshot(updatedAt: now, nextDayAt: Date(timeIntervalSince1970: cutoff), counts: total,
            etaMinutes: minutes < 0 ? nil : minutes, selectedDeckID: decks.contains { $0.id == current } ? current : nil, decks: decks)
    }
}
