import Foundation

@main struct DeckTreeSmoke {
    static func main() {
        let nodes: [[String: Any]] = [
            ["deckId": "1", "name": "Parent", "collapsed": true, "newCount": 7,
             "children": [["deckId": "2", "name": "Child", "collapsed": true,
                           "children": [["deckId": "3", "name": "Grandchild", "newCount": 3]]]]],
            ["deckId": "4", "name": "Sibling", "filtered": true]
        ]
        var decks = Deck.flatten(nodes)
        precondition(decks.map(\.id) == ["1", "2", "3", "4"])
        precondition(decks.map(\.level) == [0, 1, 2, 0])
        precondition(decks[0].newCount == 7) // Counts already include descendants.
        precondition(Deck.visible(decks).map(\.id) == ["1", "4"])
        precondition(Deck.visible(decks, search: "Grandchild").map(\.id) == ["3"])
        decks[0].collapsed = false
        precondition(Deck.visible(decks).map(\.id) == ["1", "2", "4"])
        decks[1].collapsed = false
        precondition(Deck.visible(decks).map(\.id) == ["1", "2", "3", "4"])
        precondition(!decks[2].hasChildren && decks[3].filtered)
        print("PASS: nested collapse, sibling visibility, hidden-child search, aggregate counts, complete picker tree")
    }
}
