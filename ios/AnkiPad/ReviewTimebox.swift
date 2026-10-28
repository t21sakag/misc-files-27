import Foundation

/// AnkiDroid checks the elapsed session time after each successful answer,
/// reports the configured interval, and immediately starts a new interval.
struct ReviewTimebox {
    struct Report: Equatable {
        let seconds: Int
        let answers: Int
        var message: String { "\(seconds / 60)分で\(answers)枚に回答しました。" }
    }
    private var began: TimeInterval?
    private var answers = 0
    mutating func start(now: TimeInterval) { began = now; answers = 0 }
    mutating func clear() { began = nil; answers = 0 }
    mutating func recordAnswer(limitSeconds: Int, now: TimeInterval) -> Report? {
        guard let began else { return nil }
        answers += 1
        guard limitSeconds > 0, Int(max(0, now - began)) > limitSeconds else { return nil }
        let report = Report(seconds: limitSeconds, answers: answers)
        start(now: now)
        return report
    }
}
