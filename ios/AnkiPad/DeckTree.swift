import Foundation

struct Deck: Identifiable {
    let id: String
    let name: String
    let newCount: Int
    let learnCount: Int
    let reviewCount: Int
    let level: Int
    var filtered = false
    var collapsed = false
    var hasChildren = false
    var isSelected = false
}
extension Deck {
    // Retain the complete tree for deck pickers and searches. Only the home
    // list hides descendants; counts already include children and limits.
    static func flatten(_ nodes: [[String: Any]], level: Int = 0) -> [Deck] {
        nodes.flatMap { node in
            let children = node["children"] as? [[String: Any]] ?? []
            let deck = Deck(id: node["deckId"] as? String ?? "0", name: node["name"] as? String ?? "",
                newCount: node["newCount"] as? Int ?? 0, learnCount: node["learnCount"] as? Int ?? 0,
                reviewCount: node["reviewCount"] as? Int ?? 0, level: level,
                filtered: node["filtered"] as? Bool ?? false,
                collapsed: node["collapsed"] as? Bool ?? false, hasChildren: !children.isEmpty)
            return [deck] + flatten(children, level: level + 1)
        }
    }

    static func visible(_ decks: [Deck], search: String = "") -> [Deck] {
        if !search.isEmpty { return decks.filter { $0.name.localizedStandardContains(search) } }
        var hiddenBelow: Int?
        return decks.filter { deck in
            if let level = hiddenBelow {
                if deck.level > level { return false }
                hiddenBelow = nil
            }
            if deck.collapsed && deck.hasChildren { hiddenBelow = deck.level }
            return true
        }
    }
}
