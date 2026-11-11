import Foundation

struct EngineError: Error { let message: String; var kind: Int? = nil }
enum AppText { static func localized(_ text: String) -> String { text } }
func emitTagSelection(_ value: [String: Any]) throws {
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: value))
    FileHandle.standardOutput.write(Data([10]))
}
actor Engine {
    func call(_ method: String, _ args: [String: Any] = [:]) throws -> [String: Any] {
        try emitTagSelection(["method": method, "args": args])
        guard let line = readLine(), let value = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            throw EngineError(message: "protocol")
        }
        if let ok = value["ok"] as? [String: Any] { return ok }
        throw EngineError(message: value["error"] as? String ?? "backend", kind: value["kind"] as? Int)
    }
}
@main struct TagSelectionDriver {
    static func main() async throws {
        while let line = readLine() {
            let input = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
            let op = input["op"] as? String ?? "load"
            do {
                if op == "load" {
                    let noteIDs = input["noteIDs"] as? [String] ?? []
                    let extras = input["extraCheckedTags"] as? [String] ?? []
                    let state = try await Engine().loadTagSelectionState(noteIDs: noteIDs, extraCheckedTags: extras)
                    try emitTagSelection([
                        "done": true,
                        "allTags": state.allTagList,
                        "checkedTags": state.checkedTagList,
                        "partiallySelectedTags": state.partiallySelectedTagList,
                        "indeterminateTags": state.indeterminateTags.elements
                    ])
                } else {
                    let noteIDs = input["noteIDs"] as? [String] ?? []
                    let checked = input["checkedTags"] as? [String] ?? []
                    let partial = input["partiallySelectedTags"] as? [String] ?? []
                    try await Engine().applyBatchTagSelection(noteIDs: noteIDs, checkedTags: checked, partiallySelectedTags: partial)
                    try emitTagSelection(["done": true])
                }
            } catch let error as EngineError {
                try emitTagSelection(["done": false, "error": error.message])
            }
        }
    }
}
