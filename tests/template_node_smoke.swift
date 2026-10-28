import Foundation
@main struct TemplateNodeSmoke {
    static func main() throws {
        let cases = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String: Any]]
        for item in cases {
            let actual = try TemplateNodeText.render(item["nodes"] as! [[String: Any]], frontSide: item["front"] as? String)
            precondition(actual == item["expected"] as! String, String(describing: item))
        }
        print("PASS: actual backend template nodes, unknown filters, empty text and FrontSide")
    }
}
