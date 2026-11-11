import Foundation

@main struct DeckSelectionChoicesChecks {
    static func main() {
        func deck(_ id: String, _ name: String, _ level: Int = 0, filtered: Bool = false) -> Deck {
            Deck(id: id, name: name, newCount: 0, learnCount: 0, reviewCount: 0, level: level, filtered: filtered)
        }
        let decks = [deck("1", "foo"), deck("2", "foo::bar", 1), deck("3", "foo::bar::buz", 2),
                     deck("4", "foo::buz", 1), deck("5", "buz::foo", 1), deck("6", "平日::英語", 1),
                     deck("7", "Filtered", filtered: true)]
        func ids(_ query: String, collapsed: Set<String> = []) -> [String] {
            DeckSelectionChoices.visible(decks, query: query, collapsed: collapsed).map(\.id)
        }
        precondition(ids("") == ["1","2","3","4","5","6"])
        precondition(ids("", collapsed: ["1"]) == ["1","5","6"])
        precondition(ids("buz", collapsed: ["1"]) == ["3","4"])
        precondition(ids("foo") == ["1","5"], "Ancestor-only matches do not include unrelated leaf names")
        precondition(ids("foo bar") == ["2"])
        precondition(ids("o::b") == ["2","4"], "A hierarchy filter aligns with the last separator")
        precondition(ids("foo:") == ["1","5"])
        precondition(ids("foo::") == ["2","4"])
        precondition(ids("  FOO\tBAR\n") == ["2"])
        precondition(ids("平日 英語") == ["6"])
        precondition(ids("missing").isEmpty)
        precondition(DeckSelectionChoices.visible(decks, query: "Filtered", collapsed: [], allowsFiltered: true).map(\.id) == ["7"])
        let unicode = [deck("a","Café"), deck("b","Cafe\u{0301}"), deck("c","Root😀::Word", 1), deck("d","İSTANBUL")]
        precondition(DeckSelectionChoices.visible(unicode, query: "é", collapsed: []).map(\.id) == ["a"])
        precondition(DeckSelectionChoices.visible(unicode, query: "😀::wo", collapsed: []).map(\.id) == ["c"])
        precondition(DeckSelectionChoices.visible(unicode, query: "istanbul", collapsed: [], locale: Locale(identifier: "tr_TR")).map(\.id) == ["d"])
        precondition(decks[1].collapsed == false, "Local picker folding must not mutate the home tree")
        let flattened = Deck.flatten([
            ["deckId": "10", "name": "Choice Parent",
             "children": [["deckId": "11", "name": "Child"]]]
        ])
        precondition(flattened.map(\.name) == ["Choice Parent", "Child"])
        precondition(flattened.map(\.fullName) == ["Choice Parent", "Choice Parent::Child"])
        precondition(DeckSelectionChoices.visible(flattened, query: "Choice Child", collapsed: []).map(\.id) == ["11"])
        precondition(DeckSelectionChoices.visible(flattened, query: "", collapsed: ["10"]).map(\.id) == ["10"])
        print("PASS: production deck selection filter/tree, last-leaf AND semantics, hierarchy alignment, colon typing, whitespace/case, Unicode, Turkish, filtered eligibility and local folding")
    }
}
