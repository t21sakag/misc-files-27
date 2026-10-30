import Foundation
import WidgetKit

enum WidgetData {
    static func prepareLanguage() {
        guard let container = SharedGroup.container(), let settings = SharedClientSettings.load(from: container) else { return }
        UserDefaults.standard.set(settings.language, forKey: AppLanguageChoice.preferenceKey)
    }
    static func load() -> WidgetSnapshot? {
        prepareLanguage()
        guard let container = SharedGroup.container() else { return nil }
        #if DEBUG
        let namespace = SharedClientSettings.load(from: container)?.testingNamespace
        #else
        let namespace: String? = nil
        #endif
        return try? WidgetSnapshotStore(directory: WidgetSnapshotStore.directory(in: container, testingNamespace: namespace)).load()
    }
    static func deck(_ identifier: String, in snapshot: WidgetSnapshot?) -> (WidgetProfileSnapshot, WidgetDeckSnapshot)? {
        guard let reference = WidgetDeckReference(identifier: identifier),
              let profile = snapshot?.profiles.first(where: { $0.id == reference.profileID }),
              let deck = profile.collection?.decks.first(where: { $0.id == reference.deckID }) else { return nil }
        return (profile, deck)
    }
    static var preview: WidgetSnapshot {
        let now = Date()
        let counts = WidgetCounts(new: 8, learning: 2, review: 15)
        return WidgetSnapshot(selectedProfileID: "default", profiles: [WidgetProfileSnapshot(id: "default", name: AppText.localized("既定"),
            collection: WidgetCollectionSnapshot(updatedAt: now, nextDayAt: now.addingTimeInterval(3600), counts: counts, etaMinutes: 9,
                selectedDeckID: "1", decks: [WidgetDeckSnapshot(id: "1", name: AppText.localized("学習"), counts: counts)]))])
    }
}

struct StudyWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var profileID: String? = nil
    var deckIDs: [String] = []

    var profile: WidgetProfileSnapshot? {
        let selected = profileID == nil || profileID == StudyProfileEntity.currentID ? snapshot?.selectedProfileID : profileID
        return snapshot?.profiles.first { $0.id == selected }
    }
    var homeURL: URL? { profile.map { WidgetRoute(profileID: $0.id, destination: .home).url } }
    var nextBoundary: Date? {
        let dates = (deckIDs.isEmpty ? [profile].compactMap { $0 } : deckIDs.compactMap { WidgetData.deck($0, in: snapshot)?.0 })
            .compactMap { $0.collection?.nextDayAt }.filter { $0 > date }
        return dates.min()
    }
    func timeline() -> Timeline<Self> {
        var entries = [self]
        if let boundary = nextBoundary, boundary <= date.addingTimeInterval(1800) {
            entries.append(Self(date: boundary, snapshot: snapshot, profileID: profileID, deckIDs: deckIDs))
        }
        return Timeline(entries: entries, policy: .after(min(nextBoundary ?? date.addingTimeInterval(1800), date.addingTimeInterval(1800))))
    }
}

struct ProfileWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StudyWidgetEntry { StudyWidgetEntry(date: Date(), snapshot: WidgetData.preview) }
    func snapshot(for configuration: ProfileWidgetConfiguration, in context: Context) async -> StudyWidgetEntry {
        StudyWidgetEntry(date: Date(), snapshot: WidgetData.load() ?? (context.isPreview ? WidgetData.preview : nil), profileID: configuration.profile?.id)
    }
    func timeline(for configuration: ProfileWidgetConfiguration, in context: Context) async -> Timeline<StudyWidgetEntry> {
        await snapshot(for: configuration, in: context).timeline()
    }
}

struct DeckListWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StudyWidgetEntry {
        StudyWidgetEntry(date: Date(), snapshot: WidgetData.preview, deckIDs: [WidgetDeckReference(profileID: "default", deckID: "1").identifier])
    }
    func snapshot(for configuration: DeckListWidgetConfiguration, in context: Context) async -> StudyWidgetEntry {
        let data = WidgetData.load()
        if context.isPreview && data == nil { return placeholder(in: context) }
        return StudyWidgetEntry(date: Date(), snapshot: data, deckIDs: configuration.decks.map(\.id))
    }
    func timeline(for configuration: DeckListWidgetConfiguration, in context: Context) async -> Timeline<StudyWidgetEntry> {
        await snapshot(for: configuration, in: context).timeline()
    }
}

struct DeckAnalysisWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StudyWidgetEntry { DeckListWidgetProvider().placeholder(in: context) }
    func snapshot(for configuration: DeckAnalysisWidgetConfiguration, in context: Context) async -> StudyWidgetEntry {
        let data = WidgetData.load()
        if context.isPreview && data == nil { return placeholder(in: context) }
        return StudyWidgetEntry(date: Date(), snapshot: data, deckIDs: configuration.deck.map { [$0.id] } ?? [])
    }
    func timeline(for configuration: DeckAnalysisWidgetConfiguration, in context: Context) async -> Timeline<StudyWidgetEntry> {
        await snapshot(for: configuration, in: context).timeline()
    }
}
