import Foundation

struct EngineError: Error { let message: String; var kind: Int? = nil }
enum AppText { static func localized(_ text: String) -> String { text } }
func emitDeckSelection(_ value: [String: Any]) throws {
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: value))
    FileHandle.standardOutput.write(Data([10]))
}
actor Engine {
    func call(_ method: String, _ args: [String: Any] = [:]) throws -> [String: Any] {
        try emitDeckSelection(["method": method, "args": args])
        guard let line = readLine(), let value = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            throw EngineError(message: "protocol")
        }
        if let ok = value["ok"] as? [String: Any] { return ok }
        throw EngineError(message: value["error"] as? String ?? "backend", kind: value["kind"] as? Int)
    }
}
@main struct DeckSelectionDriver {
    static func main() async throws {
        while let line = readLine() {
            let input = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
            do {
                let id = try await Engine().createDeckForSelection(input["name"] as! String, parentID: input["parent"] as? String)
                try emitDeckSelection(["done": true, "id": id])
            } catch let error as EngineError {
                try emitDeckSelection(["done": false, "error": error.message])
            }
        }
    }
}
