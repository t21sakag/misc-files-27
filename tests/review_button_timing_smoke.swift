import Foundation

@main struct ReviewButtonTimingSmoke {
    static func main() {
        var timing = ReviewButtonTiming()
        precondition(timing.accept(now: 1, intervalMilliseconds: 200))
        precondition(!timing.accept(now: 1.199, intervalMilliseconds: 200))
        precondition(timing.accept(now: 1.2, intervalMilliseconds: 200))
        precondition(!timing.accept(now: 1.3, intervalMilliseconds: 200))
        precondition(timing.accept(now: 1.4, intervalMilliseconds: 200), "Rejected clicks must not extend the window")
        precondition(timing.accept(now: 1.4, intervalMilliseconds: 0))
        precondition(!timing.accept(now: 1.3, intervalMilliseconds: 0))
        precondition(!timing.accept(now: -.infinity, intervalMilliseconds: 200))
        precondition(!timing.accept(now: .nan, intervalMilliseconds: 200))
        precondition(!timing.accept(now: Double.greatestFiniteMagnitude, intervalMilliseconds: 200))
        var other = ReviewButtonTiming()
        precondition(other.accept(now: 1.4, intervalMilliseconds: 1000))
        precondition(!other.accept(now: 2.399, intervalMilliseconds: 1000))
        precondition(other.accept(now: 2.4, intervalMilliseconds: 1000))
        print("PASS: first click, exact millisecond boundary, rejected clicks, disabled guard, invalid clock and independent session")
    }
}
