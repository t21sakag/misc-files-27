import Foundation

// Filter behavior adapted from AnkiDroid DeckFilters.kt.
// Copyright (c) 2026 Arthur Milchior. SPDX-License-Identifier: GPL-3.0-or-later.
enum DeckSelectionChoices {
    static func visible(_ decks: [Deck], query: String, collapsed: Set<String>, allowsFiltered: Bool = false,
                        locale: Locale = .current) -> [Deck] {
        let eligible = decks.filter { allowsFiltered || !$0.filtered }
        let filters = query.lowercased().components(separatedBy: CharacterSet(charactersIn: " \t\n\r\u{000B}\u{000C}"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !filters.isEmpty {
            return eligible.filter { deck in
                filters.allSatisfy { matchesName(deck.fullName, filter: $0, locale: locale) }
                    && filters.contains { matchesLeaf(deck.fullName, filter: $0, locale: locale) }
            }
        }
        let hiddenParents = eligible.filter { collapsed.contains($0.id) }.map { $0.fullName + "::" }
        return eligible.filter { deck in !hiddenParents.contains { deck.fullName.hasPrefix($0) } }
    }

    private static func contains(_ name: String, _ filter: String) -> Bool {
        (name as NSString).range(of: filter, options: .literal).location != NSNotFound
    }
    private static func matchesName(_ name: String, filter: String, locale: Locale) -> Bool {
        let trimmed = filter.hasSuffix(":") && !filter.hasSuffix("::") ? String(filter.dropLast()) : filter
        return [name.lowercased(with: locale), name.lowercased()].contains {
            contains($0, filter) || ($0 as NSString).range(of: trimmed, options: [.literal, .anchored, .backwards]).location != NSNotFound
        }
    }
    private static func matchesLeaf(_ name: String, filter: String, locale: Locale) -> Bool {
        let part = (filter as NSString).range(of: "::", options: .backwards)
        guard part.location != NSNotFound else {
            return matchesName(name.components(separatedBy: "::").last ?? name, filter: filter, locale: locale)
        }
        let target = (name as NSString).range(of: "::", options: .backwards)
        guard target.location != NSNotFound else { return false }
        let trimmed = filter.hasSuffix(":") && !filter.hasSuffix("::") ? String(filter.dropLast()) : filter
        let range = NSRange(location: target.location - part.location, length: (trimmed as NSString).length)
        guard range.location >= 0, NSMaxRange(range) <= (name as NSString).length else { return false }
        let candidate = (name as NSString).substring(with: range)
        return (candidate as NSString).compare(trimmed, options: [.caseInsensitive, .literal]) == .orderedSame
    }
}
