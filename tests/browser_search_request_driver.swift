import Foundation

@main struct SearchRequestDriver {
    static func send(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
    }
    static func main() throws {
        while let line = readLine() {
            let data = Data(line.utf8)
            do {
                let input = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                let requestData = try JSONSerialization.data(withJSONObject: input["request"]!)
                var request = try JSONDecoder().decode(BrowserSearchRequest.self, from: requestData)
                let decks = input["decks"] as? [String: String] ?? [:]
                let types = input["types"] as? [String: String] ?? [:]
                func backend(_ node: [String: Any]) throws -> [String: Any] {
                    try send(["node": node])
                    guard let reply = readLine() else { throw BrowserSearchRequest.Failure.invalidBackendResponse }
                    return try JSONSerialization.jsonObject(with: Data(reply.utf8)) as! [String: Any]
                }
                if let field = input["field"] as? [String: Any] {
                    let criterion = BrowserFieldSearchRequest(fieldName: field["name"] as! String,
                        mode: BrowserFieldSearchMode(rawValue: field["mode"] as! String)!, text: field["text"] as? String ?? "",
                        combineWithCurrent: field["combine"] as? Bool ?? true)
                    request = try criterion.buildRequest(combining: request, backend: backend)
                }
                let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request))
                let value = try request.build(deckName: { decks[$0] }, noteTypeName: { types[$0] }, backend: backend)
                try send(["query": value, "empty": request.isEmpty, "encoded": encoded])
            } catch { try send(["error": true]) }
        }
    }
}
