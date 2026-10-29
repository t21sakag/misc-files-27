import Foundation

struct ReviewButtonTiming {
    private var lastAccepted: Int64?
    mutating func accept(now: TimeInterval, intervalMilliseconds: Int) -> Bool {
        guard now.isFinite, now >= 0 else { return false }
        let milliseconds = now * 1000
        guard milliseconds.isFinite, milliseconds < Double(Int64.max) else { return false }
        let current = Int64(milliseconds.rounded(.down))
        let interval = Int64(max(0, min(1000, intervalMilliseconds)))
        if let lastAccepted, current - lastAccepted < interval { return false }
        lastAccepted = current
        return true
    }
}
