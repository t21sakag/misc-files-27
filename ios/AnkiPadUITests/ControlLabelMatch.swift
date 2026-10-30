import Foundation

/// A system button may prefix its title with a symbol attachment represented
/// as whitespace in AX. Match the whole semantic title, never a substring.
enum ControlLabelMatch {
    static func pattern(_ titles: [String]) -> String {
        precondition(!titles.isEmpty && titles.allSatisfy { !$0.isEmpty })
        return "^\\s*(?:" + titles.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")\\s*$"
    }
}
