import Foundation

@main struct ReviewTimeboxSmoke {
    static func main() {
        var box = ReviewTimebox()
        precondition(box.recordAnswer(limitSeconds: 60, now: 500) == nil)
        box.start(now: 500)
        precondition(box.recordAnswer(limitSeconds: 60, now: 500) == nil)
        precondition(box.recordAnswer(limitSeconds: 60, now: 560.9) == nil)
        precondition(box.recordAnswer(limitSeconds: 60, now: 561) == .init(seconds: 60, answers: 3))
        precondition(box.recordAnswer(limitSeconds: 60, now: 562) == nil)
        precondition(box.recordAnswer(limitSeconds: 60, now: 622) == .init(seconds: 60, answers: 2))
        box.clear()
        precondition(box.recordAnswer(limitSeconds: 60, now: 999) == nil)
        box.start(now: 1000)
        precondition(box.recordAnswer(limitSeconds: 0, now: 5000) == nil)
        box.start(now: 6000)
        precondition(box.recordAnswer(limitSeconds: 60, now: 6000) == nil)
        print("PASS: timebox boundary, successful answer counts, restart, disable and leave")
    }
}
