import Foundation

enum AppText { static func localized(_ value: String) -> String { value } }
struct EngineError: Error { let message: String }

/// Replay real backend responses through the app's actual adapter. Fail on any
/// additional call (in particular GetQueuedCards or SetCurrentDeck).
actor Engine {
    var calls: [[String: Any]]
    init(calls: [[String: Any]]) { self.calls = calls }
    func call(_ method: String, _ args: [String: Any] = [:]) throws -> [String: Any] {
        precondition(!calls.isEmpty, method)
        let next = calls.removeFirst()
        precondition(next["method"] as? String == method)
        precondition(NSDictionary(dictionary: args).isEqual(to: next["args"] as! [String: Any]), method)
        return next["result"] as! [String: Any]
    }
    func verifyComplete() { precondition(calls.isEmpty) }
}

@main struct WidgetEngineSmoke {
    static func main() async throws {
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
        let engine = Engine(calls: fixture["calls"] as! [[String: Any]])
        let now = Date(timeIntervalSince1970: fixture["now"] as! TimeInterval)
        let snapshot = try await engine.widgetSnapshot(now: now)
        precondition(snapshot.isValid && snapshot.isCurrent(at: now))
        precondition(snapshot.counts.total == fixture["count"] as! Int)
        precondition(snapshot.selectedDeckID == fixture["selected"] as? String)
        precondition(snapshot.decks.reduce(0) { $0 + $1.counts.total } > snapshot.counts.total, "Fixture must detect double-counted subdecks")
        precondition(snapshot.etaMinutes != nil)
        await engine.verifyComplete()
        print("PASS: actual engine responses through app widget adapter, root counts, preserved selection, expiry, no queue fetch or writes")
    }
}
