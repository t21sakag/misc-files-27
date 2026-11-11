import Foundation

struct WhiteboardBrush: Codable, Equatable, Identifiable {
    var colorRGBA: UInt32
    var width: Double = 3
    var clampedWidth: Double { width.isFinite ? min(40, max(1, width)) : 3 }
    var id: String { "\(colorRGBA)-\(Int((clampedWidth * 10).rounded()))" }
}

struct WhiteboardStrokeHistory<Stroke> {
    private(set) var redoStack: [Stroke] = []

    var canRedo: Bool { !redoStack.isEmpty }

    mutating func recordUserDrawingChange() {
        redoStack.removeAll()
    }

    mutating func undo(from strokes: inout [Stroke]) -> Bool {
        guard let last = strokes.popLast() else { return false }
        redoStack.append(last)
        return true
    }

    mutating func redo(into strokes: inout [Stroke]) -> Bool {
        guard let next = redoStack.popLast() else { return false }
        strokes.append(next)
        return true
    }

    mutating func clear() {
        redoStack.removeAll()
    }
}

/// Per-deck whiteboard state, matching AnkiDroid's MetaDB `whiteboardState` row for the studied deck.
struct WhiteboardPreferences: Codable, Equatable {
    var enabled = false
    var visible = true
    var stylusOnly = false
    var lightPenColor: UInt32?
    var darkPenColor: UInt32?
    var strokeWidth: Double = 3
    var lightBrushes: [WhiteboardBrush] = []
    var darkBrushes: [WhiteboardBrush] = []

    init(
        enabled: Bool = false,
        visible: Bool = true,
        stylusOnly: Bool = false,
        lightPenColor: UInt32? = nil,
        darkPenColor: UInt32? = nil,
        strokeWidth: Double = 3,
        lightBrushes: [WhiteboardBrush] = [],
        darkBrushes: [WhiteboardBrush] = []
    ) {
        self.enabled = enabled
        self.visible = visible
        self.stylusOnly = stylusOnly
        self.lightPenColor = lightPenColor
        self.darkPenColor = darkPenColor
        self.strokeWidth = Self.clampWidth(strokeWidth)
        self.lightBrushes = lightBrushes
        self.darkBrushes = darkBrushes
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, visible, stylusOnly, lightPenColor, darkPenColor, strokeWidth, lightBrushes, darkBrushes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        visible = try container.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        stylusOnly = try container.decodeIfPresent(Bool.self, forKey: .stylusOnly) ?? false
        lightPenColor = try container.decodeIfPresent(UInt32.self, forKey: .lightPenColor)
        darkPenColor = try container.decodeIfPresent(UInt32.self, forKey: .darkPenColor)
        strokeWidth = Self.clampWidth(try container.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 3)
        lightBrushes = try container.decodeIfPresent([WhiteboardBrush].self, forKey: .lightBrushes) ?? []
        darkBrushes = try container.decodeIfPresent([WhiteboardBrush].self, forKey: .darkBrushes) ?? []
    }

    static func clampWidth(_ value: Double) -> Double {
        value.isFinite ? min(40, max(1, value)) : 3
    }

    static func key(deckID: String) -> String { "whiteboard.deck." + deckID }
    static func load(_ data: Data?, legacyStylusOnly: Bool = false) -> Self {
        guard let data, let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self(stylusOnly: legacyStylusOnly) }
        return value
    }
    func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    var showsCanvas: Bool { enabled && visible }
    var clampedStrokeWidth: Double { Self.clampWidth(strokeWidth) }
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
    mutating func setStrokeWidth(_ width: Double) {
        strokeWidth = Self.clampWidth(width)
    }
    func brushes(dark: Bool) -> [WhiteboardBrush] { dark ? darkBrushes : lightBrushes }
    mutating func addBrush(colorRGBA: UInt32, width: Double? = nil, dark: Bool) {
        let resolvedWidth = Self.clampWidth(width ?? strokeWidth)
        let brush = WhiteboardBrush(colorRGBA: colorRGBA, width: resolvedWidth)
        if dark {
            if let existing = darkBrushes.firstIndex(where: { $0.id == brush.id }) { darkBrushes[existing] = brush }
            else { darkBrushes.append(brush) }
        } else {
            if let existing = lightBrushes.firstIndex(where: { $0.id == brush.id }) { lightBrushes[existing] = brush }
            else { lightBrushes.append(brush) }
        }
        setPenColor(colorRGBA, dark: dark)
        setStrokeWidth(resolvedWidth)
    }
    mutating func selectBrush(_ index: Int, dark: Bool) {
        let list = brushes(dark: dark)
        guard list.indices.contains(index) else { return }
        let brush = list[index]
        setPenColor(brush.colorRGBA, dark: dark)
        setStrokeWidth(brush.clampedWidth)
    }
    mutating func removeBrush(at index: Int, dark: Bool) {
        if dark {
            guard darkBrushes.indices.contains(index) else { return }
            darkBrushes.remove(at: index)
        } else {
            guard lightBrushes.indices.contains(index) else { return }
            lightBrushes.remove(at: index)
        }
    }
}
