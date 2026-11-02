import Foundation

enum DriverFailure: Error { case backend, protocolFailure }
func sendForgetMessage(_ value: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: value)
    FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
}
actor Engine {
    func call(_ method: String, _ arguments: [String: Any]) throws -> [String: Any] {
        try sendForgetMessage(["method": method, "args": arguments])
        guard let line = readLine(), let reply = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { throw DriverFailure.protocolFailure }
        guard let result = reply["ok"] as? [String: Any] else { throw DriverFailure.backend }
        return result
    }
    func backup() throws { _ = try call("_backup", [:]) }
}
@main struct BrowserForgetDriver {
    static func main() async throws {
        while let line = readLine() {
            let input = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
            let options = BrowserForgetOptions(restorePosition: input["restore"] as! Bool, resetCounts: input["counts"] as! Bool)
            do {
                try await Engine().forgetBrowserCards(input["ids"] as! [String], options: options)
                try sendForgetMessage(["done": true])
            } catch { try sendForgetMessage(["done": false]) }
        }
    }
}
