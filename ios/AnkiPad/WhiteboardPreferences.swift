import Foundation

/// Per-deck whiteboard state, matching AnkiDroid's MetaDB `whiteboardState` row for the studied deck.
struct WhiteboardPreferences: Codable, Equatable {
    var enabled = false
    var visible = true
    var stylusOnly = false
    var lightPenColor: UInt32?
    var darkPenColor: UInt32?

    static func key(deckID: String) -> String { "whiteboard.deck." + deckID }
    static func load(_ data: Data?, legacyStylusOnly: Bool = false) -> Self {
        guard let data, let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self(stylusOnly: legacyStylusOnly) }
        return value
    }
    func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    var showsCanvas: Bool { enabled && visible }
    /// Upstream ties visibility to the enabled state whenever the whiteboard itself is toggled.
    mutating func toggleEnabled() {
        enabled.toggle()
        visible = enabled
    }
    mutating func toggleVisible() {
        guard enabled else { return }
        visible.toggle()
    }
    func penColor(dark: Bool) -> UInt32? { dark ? darkPenColor : lightPenColor }
    mutating func setPenColor(_ rgba: UInt32, dark: Bool) {
        if dark { darkPenColor = rgba } else { lightPenColor = rgba }
    }
}
