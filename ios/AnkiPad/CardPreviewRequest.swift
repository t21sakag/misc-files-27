import Foundation

struct CardPreviewRequest: Identifiable {
    let id = UUID()
    let ids: [String]
    let initialIndex: Int

    init(ids: [String], initialIndex: Int = 0) {
        self.ids = ids
        self.initialIndex = min(max(0, initialIndex), max(0, ids.count - 1))
    }

    /// The pinned browser previews all rows for zero/one selection, starting
    /// at the selected row. Multiple selected rows expand to all their cards.
    /// In notes mode the all-rows path uses one representative card per note.
    static func browser(rowIDs: [String], selected: [String], notesMode: Bool,
                        cardsOfNote: (String) throws -> [String]) throws -> CardPreviewRequest {
        let available = Set(rowIDs)
        var seen = Set<String>()
        let orderedSelection = selected.filter { available.contains($0) && seen.insert($0).inserted }
        let multiple = orderedSelection.count > 1
        let targets = multiple ? orderedSelection : rowIDs
        let start = multiple ? 0 : orderedSelection.first.flatMap { rowIDs.firstIndex(of: $0) } ?? 0
        guard notesMode else { return CardPreviewRequest(ids: targets, initialIndex: start) }
        var cards: [String] = []
        for note in targets {
            let siblings = try cardsOfNote(note)
            if multiple { cards += siblings }
            else {
                guard let first = siblings.first else { throw EngineError(message: AppText.localized("カードがありません")) }
                cards.append(first)
            }
        }
        return CardPreviewRequest(ids: cards, initialIndex: start)
    }
}

/// Preserve the pinned browser's LinkedHashSet selection order with SwiftUI's Set binding.
enum BrowserSelectionOrder {
    static func updating(previous: [String], next: Set<String>, rowIDs: [String]) -> [String] {
        let available = Set(rowIDs)
        var seen = Set<String>()
        let retained = previous.filter { next.contains($0) && available.contains($0) && seen.insert($0).inserted }
        return retained + rowIDs.filter { next.contains($0) && seen.insert($0).inserted }
    }
}
