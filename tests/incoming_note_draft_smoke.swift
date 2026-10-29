import Foundation

@main struct IncomingNoteDraftSmoke {
    static func main() {
        let plain = IncomingNoteDraft(subject: "A & <B>", text: "line1\r\nline2\rline3\nend", tags: "one 日本語")
        precondition(plain.fields == ["A &amp; &lt;B&gt;", "line1<br>line2<br>line3<br>end"])
        precondition(plain.tags == "one 日本語" && plain.requiredFieldCount == 2)
        let body = IncomingNoteDraft(subject: "", text: "本文 <literal>")
        precondition(body.fields == ["本文 &lt;literal&gt;", ""] && body.requiredFieldCount == 1)
        precondition(IncomingNoteDraft(front: "<b>raw</b>", isHTML: true).fields[0] == "<b>raw</b>")
        func draft(_ query: String) -> IncomingNoteDraft { IncomingNoteDraft(url: URL(string: "studyclient://x-callback-url/addnote?" + query)!)! }
        let decoded = draft("front=A+B%2BC%2520&front=ignored&back=%E6%97%A5%E6%9C%AC%E8%AA%9E&tags=x+y&x-success=https://invalid.example/")
        precondition(decoded.front == "A B+C%20" && decoded.back == "日本語" && decoded.tags == "x y")
        precondition(draft("subject=subject&text=body").fields == ["subject", "body"])
        precondition(draft("text=body").fields == ["body", ""])
        precondition(draft("front=&subject=ignored&text=ignored").fields == ["", ""])
        precondition(draft("front=%3Cb%3Eraw%3C/b%3E&html=TRUE").fields[0] == "<b>raw</b>")
        precondition(draft("front=%3Cb%3Eraw%3C/b%3E&html=false").fields[0] == "&lt;b&gt;raw&lt;/b&gt;")
        for value in ["anki://x-callback-url/addnote?front=x", "studyclient://other/addnote", "studyclient://x-callback-url/browser?search=x", "https://x-callback-url/addnote"] {
            precondition(IncomingNoteDraft(url: URL(string: value)!) == nil)
        }
        print("PASS: incoming text mapping, HTML opt-in, literal escaping, newlines, tags, first-value/plus/one-decode URL semantics and route rejection")
    }
}
