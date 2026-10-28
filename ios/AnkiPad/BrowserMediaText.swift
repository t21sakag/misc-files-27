import Foundation

enum BrowserMediaText {
    // The backend marks rendered audio references with these delimiters.
    // Match AnkiDroid's BrowserMultiColumnAdapter.removeSounds().
    private static let sounds = try! NSRegularExpression(pattern: "🔉(.*?)🔉")
    static func display(_ text: String, showMediaFilenames: Bool) -> String {
        guard !showMediaFilenames else { return text }
        return sounds.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }
}
