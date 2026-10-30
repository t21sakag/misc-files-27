import Foundation

@main struct ControlLabelMatchSmoke {
    static func main() throws {
        let pattern = ControlLabelMatch.pattern(["Add Widget", "Edit", "完了", "A+B"])
        let expression = try NSRegularExpression(pattern: pattern)
        func matches(_ text: String) -> Bool {
            expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
        // The first value is the exact AX label observed in 41037745804.
        for label in [" Add Widget", "\u{00a0}Add Widget \n", "Edit", "完了", "A+B"] { precondition(matches(label), label) }
        for label in ["Remove Widget", "Add Widget Later", "Other Edit", "AAB", "Add Widgets"] { precondition(!matches(label), label) }
        print("PASS: observed symbol-space title and Unicode whitespace match; unrelated titles and regex metacharacters remain exact")
    }
}
