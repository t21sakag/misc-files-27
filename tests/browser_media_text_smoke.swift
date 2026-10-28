import Foundation

@main struct BrowserMediaTextSmoke {
    static func main() {
        let input = "写真.png literal.mp3 🔉音声.mp3🔉 middle 🔉second.wav🔉 end"
        precondition(BrowserMediaText.display(input, showMediaFilenames: true) == input)
        precondition(BrowserMediaText.display(input, showMediaFilenames: false) == "写真.png literal.mp3  middle  end")
        precondition(BrowserMediaText.display("unpaired 🔉literal", showMediaFilenames: false) == "unpaired 🔉literal")
        precondition(BrowserMediaText.display("🔉🔉", showMediaFilenames: false).isEmpty)
        print("PASS: backend sound markers, Unicode, multiple sounds and literal filenames")
    }
}
