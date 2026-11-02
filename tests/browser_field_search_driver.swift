import Foundation

@main struct FieldSearchDriver {
    static func send(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
    }
    static func main() throws {
        while let line = readLine() {
            let input = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
            let request = BrowserFieldSearchRequest(fieldName: input["field"] as! String,
                mode: BrowserFieldSearchMode(rawValue: input["mode"] as! String)!, text: input["text"] as? String ?? "",
                currentSearch: input["current"] as? String ?? "", combineWithCurrent: input["combine"] as? Bool ?? false)
            do {
                let query = try request.build { node in
                    try send(["node": node])
                    guard let reply = readLine() else { throw BrowserFieldSearchRequest.Failure.invalidBackendResponse }
                    return try JSONSerialization.jsonObject(with: Data(reply.utf8)) as! [String: Any]
                }
                try send(["query": query])
            } catch { try send(["error": true]) }
        }
    }
}
