import Foundation

@main enum CollectionPageScanChecks {
    static func search(_ pages: [[String]], from start: Int, wanted: Set<String>, first: String? = nil)
        -> (complete: Bool, position: Int, seen: Set<String>) {
        var state = CollectionPageScanState(), position = start, seen: Set<String> = []
        for _ in 0..<12 {
            let page = pages[position]
            seen.formUnion(page)
            if let first {
                if page.contains(first) { return (true, position, seen) }
            } else if wanted.isSubset(of: seen) { return (true, position, seen) }
            guard let towardsStart = state.nextDirection(after: page.joined(separator: "|")) else {
                return (false, position, seen)
            }
            position = towardsStart ? max(0, position - 1) : min(pages.count - 1, position + 1)
        }
        fatalError("Traversal failed to terminate within the fixture page bound")
    }

    static func main() {
        let bounds = CGRect(x: 120, y: 260, width: 580, height: 660)
        let lastCell = CGRect(x: 136, y: 752.5, width: 548, height: 147.5)
        precondition(CollectionPageScanState.containsFullyMountedCell(lastCell, in: bounds))
        precondition(!CGRect(x: 120, y: 410, width: 580, height: 430).contains(lastCell),
                     "Gesture safety insets must not exclude the mounted end cell")
        precondition(!CollectionPageScanState.containsFullyMountedCell(CGRect(x: 136, y: 800, width: 548, height: 147.5), in: bounds))
        precondition(!CollectionPageScanState.containsFullyMountedCell(.zero, in: bounds))
        precondition(!CollectionPageScanState.containsFullyMountedCell(CGRect(x: 136, y: .infinity, width: 548, height: 147.5), in: bounds))
        let forward = [["row0", "row1"], ["row2", "row3"], ["row3", "row4"]]
        let wanted = Set((0..<5).map { "row" + String($0) })
        let narrow = (0..<5).map { ["row" + String($0)] }
        for pages in [forward, Array(forward.reversed()), narrow, Array(narrow.reversed())] {
            for start in pages.indices {
                let result = search(pages, from: start, wanted: wanted)
                precondition(result.complete && result.seen == wanted)
                let restored = search(pages, from: result.position, wanted: [], first: "row0")
                precondition(restored.complete && pages[restored.position].contains("row0"))
                let missing = search(pages, from: start, wanted: wanted.union(["missing"]))
                precondition(!missing.complete && missing.seen == wanted)
            }
        }
        let single = search([["row0"]], from: 0, wanted: ["missing"])
        precondition(!single.complete && single.seen == ["row0"])
        print("PASS: actual collection traversal covers every page from every start/order, restores the requested first row, and fails finitely for missing targets")
    }
}
