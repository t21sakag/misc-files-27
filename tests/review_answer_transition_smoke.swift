import Foundation
@main struct ReviewTransitionSmoke {
    static func main() {
        let front = "<div>sample</div><br><div>An example</div>"
        let back = front + "<hr id=answer><div>意味</div><br><div>例文</div>"
        precondition(ReviewAnswerTransition.pendingHTML(question: front, answer: back)?.contains("inert aria-hidden") == true)
        for value in ["different", front + "<div>answer</div>", back + "<script>alert(1)</script>", back + "<img src=x>", back + "<div onclick='action()'>x</div>", back + "<input id=typeans>", front + "<hr id=answer>\\(x\\)"] {
            precondition(ReviewAnswerTransition.pendingHTML(question: front, answer: value) == nil)
        }
        precondition(ReviewAnswerTransition.pendingHTML(question: "<div>x</div\n<div>y</div>", answer: "<div>x</div\n<div>y</div><hr id=answer>z") == nil)
        print("PASS plain FrontSide reveal and dynamic/typed/malformed fallback")
    }
}
