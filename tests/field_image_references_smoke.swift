import Foundation

@main struct FieldImageReferencesSmoke {
    static func main() {
        func sources(_ html: String) -> [String] { FieldImageReference.extract(html).map(\.source) }
        precondition(sources("<IMG alt='a > b src=wrong.png' SRC=\"right&amp;one.png\">") == ["right&one.png"])
        precondition(sources("<!-- <img src='hidden.png'> --><script>let x='<img src=bad.png>';</script><img src=ok.png>") == ["ok.png"])
        precondition(sources("<textarea><img src=bad.png></textarea><style>x{content:'<img src=bad.png>'}</style>") == [])
        precondition(sources("<img data-src=bad.png><img src='&#x65;&#97;.png'><img\nsrc='a%20b.png'>") == ["ea.png", "a b.png"])
        precondition(sources("<img src='&amp;quot;.png'>") == ["&quot;.png"])
        precondition(sources("<img src='https://a/b.png'><img src='../x.png'><img src='%2e%2e%2fx.png'><img src='x&#0;.png'>") == [])
        precondition(sources("<img src='first.png' src='second.png'>") == ["first.png"])
        let html = "🙂<p><img title='x > y' src='old.png' width=42></p>"
        let refs = FieldImageReference.extract(html)
        precondition(refs.count == 1)
        let replaced = (html as NSString).replacingCharacters(in: refs[0].range, with: "new.png")
        precondition(replaced == "🙂<p><img title='x > y' src='new.png' width=42></p>")
        print("Field image references: parsing, decoding, exclusions and UTF-16 replacement passed")
    }
}
