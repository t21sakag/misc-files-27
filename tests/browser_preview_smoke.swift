import Foundation

enum AppText { static func localized(_ text: String) -> String { text } }
struct EngineError: Error { let message: String }
actor Engine {
    let cards: [String: [String]]
    var calls: [String] = []
    init(_ cards: [String: [String]]) { self.cards = cards }
    func call(_ method: String, _ args: [String: Any]) throws -> [String: Any] {
        precondition(method == "NotesService.CardsOfNote")
        let note = args["nid"] as! String
        calls.append(note)
        guard let ids = cards[note] else { throw EngineError(message: "Injected read failure") }
        return ["cids": ids]
    }
}
@main struct BrowserPreviewSmoke {
    static func main() async throws {
        let rows = (0..<240).map { "card-\($0)" }
        func cards(_ selected: [String]) throws -> CardPreviewRequest {
            try CardPreviewRequest.browser(rowIDs: rows, selected: selected, notesMode: false) { _ in
                preconditionFailure("Cards mode must not query note IDs")
            }
        }
        let ordering = ["a", "b", "c", "d"]
        var selection = BrowserSelectionOrder.updating(previous: [], next: ["c"], rowIDs: ordering)
        selection = BrowserSelectionOrder.updating(previous: selection, next: ["a", "c"], rowIDs: ordering)
        precondition(selection == ["c", "a"])
        selection = BrowserSelectionOrder.updating(previous: selection, next: ["a"], rowIDs: ordering)
        selection = BrowserSelectionOrder.updating(previous: selection, next: ["a", "c"], rowIDs: ordering)
        precondition(selection == ["a", "c"])
        selection = BrowserSelectionOrder.updating(previous: selection, next: Set(ordering), rowIDs: ordering)
        precondition(selection == ["a", "c", "b", "d"])
        precondition(BrowserSelectionOrder.updating(previous: selection, next: ["deleted", "c"], rowIDs: ["c", "d"]) == ["c"])
        let all = try cards([])
        precondition(all.ids == rows && all.initialIndex == 0)
        let late = try cards([rows[175]])
        precondition(late.ids == rows && late.initialIndex == 175)
        let multiple = try cards([rows[201], rows[3]])
        precondition(multiple.ids == [rows[201], rows[3]] && multiple.initialIndex == 0)
        let stale = try cards(["deleted", rows[120], rows[120]])
        precondition(stale.ids == rows && stale.initialIndex == 120)
        let empty = try CardPreviewRequest.browser(rowIDs: [], selected: ["deleted"], notesMode: true) { _ in preconditionFailure() }
        precondition(empty.ids.isEmpty && empty.initialIndex == 0)
        precondition(CardPreviewRequest(ids: ["a", "b"], initialIndex: -3).initialIndex == 0)
        precondition(CardPreviewRequest(ids: ["a", "b"], initialIndex: 500).initialIndex == 1)
        precondition(CardPreviewRequest(ids: [], initialIndex: 5).initialIndex == 0)
        let siblings = ["n1": ["c1a", "c1b"], "n2": ["c2a", "c2b"], "n3": ["c3a"]]
        try await checkNotes(["n1", "n2", "n3"], cards: siblings)
        do {
            _ = try CardPreviewRequest.browser(rowIDs: ["empty"], selected: [], notesMode: true) { _ in [] }
            preconditionFailure("Missing representative must not silently shift the initial row")
        } catch is EngineError {}
        let broken = Engine([:])
        do {
            _ = try await broken.browserPreview(rowIDs: ["missing"], selected: [], notesMode: true)
            preconditionFailure("Read failure was hidden")
        } catch is EngineError {}
        if CommandLine.arguments.count == 2 {
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let fixture = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            try await checkNotes(fixture["rows"] as! [String], cards: fixture["cards"] as! [String: [String]])
        }
        print("PASS: production browser preview factory/adapter: all240 rows, late single start, insertion-ordered subset, representative vs siblings, stale IDs, empty/clamped requests and read failure; transport simulated")
    }
    static func checkNotes(_ rows: [String], cards: [String: [String]]) async throws {
        precondition(rows.count >= 3 && cards[rows[0]]!.count > 1 && cards[rows[1]]!.count > 1)
        let engine = Engine(cards)
        let all = try await engine.browserPreview(rowIDs: rows, selected: [], notesMode: true)
        let representatives = rows.map { cards[$0]!.first! }
        precondition(all.ids == representatives && all.initialIndex == 0)
        let single = try await engine.browserPreview(rowIDs: rows, selected: [rows[1]], notesMode: true)
        precondition(single.ids == representatives && single.initialIndex == 1)
        let subset = try await engine.browserPreview(rowIDs: rows, selected: [rows[1], rows[0]], notesMode: true)
        precondition(subset.ids == cards[rows[1]]! + cards[rows[0]]! && subset.initialIndex == 0)
        let requested = await engine.calls
        precondition(requested == rows + rows + [rows[1], rows[0]])
        print("PASS: production notes preview uses first native card per row; multiple notes expand siblings in selection order")
    }
}
