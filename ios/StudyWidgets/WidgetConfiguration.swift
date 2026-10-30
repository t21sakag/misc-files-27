import AppIntents
import Foundation

struct StudyProfileEntity: AppEntity {
    static let currentID = "current"
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Profile", table: "WidgetConfiguration"))
    static var defaultQuery = StudyProfileQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var current: Self { Self(id: currentID, name: AppText.localized("現在のプロファイル")) }
}

struct StudyProfileQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [StudyProfileEntity] {
        let snapshot = WidgetData.load()
        // Retain an unavailable configured identity as a tombstone. Resolving
        // it as nil would silently redirect the widget to the active profile.
        return identifiers.compactMap { id in
            if id == StudyProfileEntity.currentID { return .current }
            guard WidgetRoute.validProfileID(id) else { return nil }
            return StudyProfileEntity(id: id, name: snapshot?.profiles.first { $0.id == id }?.name ?? AppText.localized("プロファイルが見つかりません"))
        }
    }
    func suggestedEntities() async throws -> [StudyProfileEntity] {
        let snapshot = WidgetData.load()
        return [.current] + (snapshot?.profiles.map { StudyProfileEntity(id: $0.id, name: $0.name) } ?? [])
    }
    func defaultResult() async -> StudyProfileEntity? { WidgetData.prepareLanguage(); return .current }
}

struct StudyDeckEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Deck", table: "WidgetConfiguration"))
    static var defaultQuery = StudyDeckQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct StudyDeckQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [StudyDeckEntity] {
        let snapshot = WidgetData.load()
        return identifiers.compactMap { id in
            guard WidgetDeckReference(identifier: id) != nil else { return nil }
            let value = WidgetData.deck(id, in: snapshot)
            return StudyDeckEntity(id: id, name: value.map { $0.0.name + " · " + $0.1.name } ?? AppText.localized("デッキが見つかりません"))
        }
    }
    func suggestedEntities() async throws -> [StudyDeckEntity] {
        let snapshot = WidgetData.load()
        return snapshot?.profiles.flatMap { profile in
            profile.collection?.decks.map { deck in
                StudyDeckEntity(id: WidgetDeckReference(profileID: profile.id, deckID: deck.id).identifier, name: profile.name + " · " + deck.name)
            } ?? []
        } ?? []
    }
    func defaultResult() async -> StudyDeckEntity? {
        let snapshot = WidgetData.load()
        guard let profile = snapshot?.profiles.first(where: { $0.id == snapshot?.selectedProfileID }),
              let id = profile.collection?.selectedDeckID else { return nil }
        return try? await entities(for: [WidgetDeckReference(profileID: profile.id, deckID: id).identifier]).first
    }
}

struct ProfileWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("Study profile", table: "WidgetConfiguration")
    @Parameter(title: LocalizedStringResource("Profile", table: "WidgetConfiguration")) var profile: StudyProfileEntity?
}

struct DeckListWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("Study decks", table: "WidgetConfiguration")
    @Parameter(title: LocalizedStringResource("Decks in display order", table: "WidgetConfiguration"), default: []) var decks: [StudyDeckEntity]
}

struct DeckAnalysisWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("Deck counts", table: "WidgetConfiguration")
    @Parameter(title: LocalizedStringResource("Deck", table: "WidgetConfiguration")) var deck: StudyDeckEntity?
}
