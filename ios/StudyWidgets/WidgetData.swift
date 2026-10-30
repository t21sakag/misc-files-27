import Foundation
import WidgetKit

enum WidgetData {
    static func prepareLanguage() {
        #if DEBUG
        WidgetProbe.record("language.start")
        #endif
        guard let container = SharedGroup.container(), let settings = SharedClientSettings.load(from: container) else { return }
        UserDefaults.standard.set(settings.language, forKey: AppLanguageChoice.preferenceKey)
    }
    static func load(source: String = "entity-query") -> WidgetSnapshot? {
        #if DEBUG
        WidgetProbe.record("snapshot.start", values: ["source": source])
        #endif
        prepareLanguage()
        guard let container = SharedGroup.container() else {
            #if DEBUG
            WidgetProbe.record("snapshot.no-group", values: ["source": source])
            #endif
            return nil
        }
        #if DEBUG
        let namespace = SharedClientSettings.load(from: container)?.testingNamespace
        WidgetProbe.record("snapshot.group", values: ["source": source, "namespace": namespace == nil ? "absent" : "present"])
        #else
        let namespace: String? = nil
        #endif
        let store = WidgetSnapshotStore(directory: WidgetSnapshotStore.directory(in: container, testingNamespace: namespace))
        do {
            let value = try store.load()
            #if DEBUG
            let count = value?.profiles.first { $0.id == value?.selectedProfileID }?.collection?.counts.total
            WidgetProbe.record("snapshot.read", values: ["source": source, "available": value == nil ? "no" : "yes", "count": count.map { String($0) } ?? "unavailable"])
            #endif
            return value
        } catch {
            #if DEBUG
            WidgetProbe.record("snapshot.error", values: ["source": source, "code": String((error as NSError).code)])
            #endif
            return nil
        }
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
        StudyWidgetEntry(date: Date(), snapshot: WidgetData.load(source: context.isPreview ? "profile.preview" : "profile.snapshot") ?? (context.isPreview ? WidgetData.preview : nil), profileID: configuration.profile?.id)
    }
    func timeline(for configuration: ProfileWidgetConfiguration, in context: Context) async -> Timeline<StudyWidgetEntry> {
        #if DEBUG
        WidgetProbe.record("timeline.request", values: ["kind": "profile"])
        #endif
        return await snapshot(for: configuration, in: context).timeline()
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
