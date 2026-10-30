import AppIntents
import Foundation
import WidgetKit

@main struct WidgetTimelineSmoke {
    static func main() async throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let secondID = UUID().uuidString
        let counts = WidgetCounts(new: 2, learning: 1, review: 3)
        func collection(_ name: String) -> WidgetCollectionSnapshot {
            WidgetCollectionSnapshot(updatedAt: now, nextDayAt: now.addingTimeInterval(600), counts: counts, etaMinutes: 2,
                selectedDeckID: "1", decks: [WidgetDeckSnapshot(id: "1", name: name, counts: counts)])
        }
        let snapshot = WidgetSnapshot(selectedProfileID: secondID, profiles: [
            WidgetProfileSnapshot(id: "default", name: "First", collection: collection("First deck")),
            WidgetProfileSnapshot(id: secondID, name: "Second", collection: collection("Second deck"))])
        let firstDeck = WidgetDeckReference(profileID: "default", deckID: "1").identifier
        let secondDeck = WidgetDeckReference(profileID: secondID, deckID: "1").identifier
        precondition(WidgetData.deck(firstDeck, in: snapshot)?.1.name == "First deck")
        precondition(WidgetData.deck(secondDeck, in: snapshot)?.1.name == "Second deck")
        precondition(WidgetData.deck("default:999", in: snapshot) == nil)
        let entry = StudyWidgetEntry(date: now, snapshot: snapshot)
        precondition(entry.profile?.id == secondID)
        precondition(WidgetRoute(url: entry.homeURL!)?.profileID == secondID)
        let fixed = StudyWidgetEntry(date: now, snapshot: snapshot, profileID: "default")
        precondition(fixed.profile?.id == "default")
        let missing = StudyWidgetEntry(date: now, snapshot: snapshot, profileID: UUID().uuidString)
        precondition(missing.profile == nil && missing.homeURL == nil)
        let timeline = entry.timeline()
        precondition(timeline.entries.count == 2)
        precondition(timeline.entries[1].date == now.addingTimeInterval(600))
        precondition(!timeline.entries[1].profile!.collection!.isCurrent(at: timeline.entries[1].date))
        let order = StudyWidgetEntry(date: now, snapshot: snapshot, deckIDs: [secondDeck, firstDeck])
        precondition(order.deckIDs.compactMap { WidgetData.deck($0, in: snapshot)?.0.id } == [secondID,"default"])
        let references = try await StudyDeckQuery().entities(for: [firstDeck, secondDeck])
        precondition(references.map(\.id) == [firstDeck,secondDeck], "Unavailable configured decks must retain identity, never select another profile")
        let profiles = try await StudyProfileQuery().entities(for: [secondID])
        precondition(profiles.first?.id == secondID)
        print("PASS: actual WidgetKit timeline expiry, profile-specific equal deck IDs, selection order, missing-profile fail-closed and AppEntity tombstones")
    }
}
