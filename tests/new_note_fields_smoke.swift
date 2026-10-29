import Foundation

@main struct NewNoteFieldsSmoke {
    static func main() {
        let original = ["front", "back", "日本語 <extra>"]
        var buffer = NewNoteFields.retaining(original, in: [])
        let smaller = NewNoteFields.applying(buffer, to: ["", ""])
        precondition(smaller == ["front", "back"])
        precondition(NewNoteFields.unmapped(buffer, fieldCount: smaller.count) == [2])
        buffer = NewNoteFields.retaining(["edited front", ""], in: buffer)
        precondition(NewNoteFields.applying(buffer, to: ["", "", ""]) == ["edited front", "", "日本語 <extra>"])
        // Explicitly clearing an extra field must remain cleared when returning
        // to a wider type. Empty fields must not resurrect stale defaults.
        buffer[2] = ""
        precondition(NewNoteFields.unmapped(buffer, fieldCount: 2).isEmpty)
        precondition(NewNoteFields.applying(buffer, to: ["sticky", "sticky", "sticky"]) == ["edited front", "", ""])
        precondition(NewNoteFields.applying([], to: ["sticky default"]) == ["sticky default"])
        precondition(NewNoteFields.applying(buffer, to: []).isEmpty)
        precondition(NewNoteFields.unmapped(buffer, fieldCount: 0) == [0])
        precondition(NewNoteFields.retaining([], in: buffer) == buffer)
        print("PASS: new-note field shrink/restore, edited and cleared values, unmapped save guard and untouched defaults beyond supplied fields")
    }
}
