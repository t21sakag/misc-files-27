import Foundation

@main
struct WhiteboardPreferencesSmoke {
    static func main() {
        var value = WhiteboardPreferences.load(nil, legacyStylusOnly: true)
        precondition(!value.enabled && value.visible && value.stylusOnly && !value.showsCanvas)
        precondition(WhiteboardPreferences.load(Data("broken".utf8)) == WhiteboardPreferences())

        value.toggleVisible()
        precondition(value.visible, "hiding requires an enabled whiteboard")
        value.toggleEnabled()
        precondition(value.enabled && value.visible && value.showsCanvas)
        value.toggleVisible()
        precondition(value.enabled && !value.visible && !value.showsCanvas)
        value.toggleEnabled()
        precondition(!value.enabled && !value.visible)
        value.toggleEnabled()
        precondition(value.showsCanvas, "re-enabling shows the whiteboard again")

        value.setPenColor(0xFF0000FF, dark: false)
        value.setPenColor(0x00FF00FF, dark: true)
        precondition(value.penColor(dark: false) == 0xFF0000FF && value.penColor(dark: true) == 0x00FF00FF)

        let restored = WhiteboardPreferences.load(value.encoded())
        precondition(restored == value)
        precondition(WhiteboardPreferences.key(deckID: "42") != WhiteboardPreferences.key(deckID: "43"))

        // Legacy payload without strokeWidth / brushes must decode with default strokeWidth=3 and empty brushes
        let legacyJSON = #"{"enabled":true,"visible":false,"stylusOnly":true,"lightPenColor":4278190335}"#.data(using: .utf8)!
        let fromLegacy = WhiteboardPreferences.load(legacyJSON)
        precondition(fromLegacy.enabled && !fromLegacy.visible && fromLegacy.stylusOnly)
        precondition(fromLegacy.clampedStrokeWidth == 3)
        precondition(fromLegacy.brushes(dark: false).isEmpty && fromLegacy.brushes(dark: true).isEmpty)

        // Per-deck brush persistence and selection (XML078 / XML108)
        value.addBrush(colorRGBA: 0x112233FF, width: 12, dark: false)
        value.addBrush(colorRGBA: 0x445566FF, width: 6, dark: false)
        precondition(value.brushes(dark: false).count == 2)
        precondition(value.penColor(dark: false) == 0x445566FF && value.clampedStrokeWidth == 6)
        value.selectBrush(0, dark: false)
        precondition(value.penColor(dark: false) == 0x112233FF && value.clampedStrokeWidth == 12)
        let brushRestored = WhiteboardPreferences.load(value.encoded())
        precondition(brushRestored == value)
        value.removeBrush(at: 0, dark: false)
        precondition(value.brushes(dark: false).count == 1)

        // Independent WhiteboardStrokeHistory Undo/Redo (XML289 / XML290)
        var strokes = ["stroke-1", "stroke-2"]
        var history = WhiteboardStrokeHistory<String>()
        precondition(!history.canRedo)
        precondition(history.undo(from: &strokes))
        precondition(strokes == ["stroke-1"] && history.canRedo)
        precondition(history.redo(into: &strokes))
        precondition(strokes == ["stroke-1", "stroke-2"] && !history.canRedo)
        precondition(history.undo(from: &strokes))
        history.recordUserDrawingChange()
        precondition(!history.canRedo, "New user stroke must clear redo stack")

        print("whiteboard preferences smoke passed")
    }
}
