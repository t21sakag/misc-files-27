import Foundation

@main struct BrowserLinkSmoke {
    struct Example: Decodable {
        let url: String
        let recognized: Bool
        let search: String?
    }
    static func main() throws {
        let path = URL(fileURLWithPath: CommandLine.arguments[1])
        for example in try JSONDecoder().decode([Example].self, from: Data(contentsOf: path)) {
            let link = BrowserLink(url: URL(string: example.url)!)
            precondition((link != nil) == example.recognized, example.url)
            if example.recognized { precondition(link?.search == example.search, example.url) }
        }
        var inbox = BrowserLinkInbox()
        let first = URL(string: "studyclient://x-callback-url/browser?search=first")!
        let second = URL(string: "anki://x-callback-url/browser?search=second")!
        precondition(inbox.receive(first))
        for _ in 0..<3 { precondition(inbox.take(canPresent: false) == nil) }
        precondition(inbox.pending == BrowserLink(search: "first"))
        precondition(!inbox.receive(URL(string: "anki://x-callback-url/delete")!))
        precondition(inbox.pending == BrowserLink(search: "first"))
        precondition(inbox.receive(second))
        precondition(inbox.take(canPresent: true) == BrowserLink(search: "second"))
        precondition(inbox.pending == nil && inbox.take(canPresent: true) == nil)
        precondition(inbox.receive(URL(string: "anki://x-callback-url/browser?search=")!))
        precondition(inbox.take(canPresent: true) == BrowserLink(search: ""))
        print("PASS: browser URI contract, Android percent/plus/first-value semantics, missing versus empty search, deferred/latest/one-shot inbox and invalid-URL preservation")
    }
}
