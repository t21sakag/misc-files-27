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
        print("whiteboard preferences smoke passed")
    }
}
