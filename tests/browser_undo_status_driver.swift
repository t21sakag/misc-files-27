import Foundation

enum UndoDriverFailure: Error { case backend, protocolFailure }

func sendUndoMessage(_ value: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}

actor Engine {
    func call(_ method: String) throws -> [String: Any] {
        try sendUndoMessage(["method": method])
        guard let line = readLine(),
              let response = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            throw UndoDriverFailure.protocolFailure
        }
        guard let value = response["ok"] as? [String: Any] else { throw UndoDriverFailure.backend }
        return value
    }
}

@main struct BrowserUndoStatusDriver {
    static func main() async throws {
        let engine = Engine()
        while readLine() != nil {
            do {
                let status = try await engine.browserUndoStatus()
                try sendUndoMessage(["undo": status.undo, "redo": status.redo])
            } catch { try sendUndoMessage(["error": true]) }
        }
    }
}
