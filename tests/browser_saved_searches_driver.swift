import Foundation

enum SavedSearchDriverFailure: Error { case backend, protocolFailure }
enum AppText { static func localized(_ value: String) -> String { value } }

func sendSavedSearchMessage(_ value: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}

actor Engine {
    private func request(_ value: [String: Any]) throws -> [String: Any] {
        try sendSavedSearchMessage(value)
        guard let line = readLine(),
              let reply = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            throw SavedSearchDriverFailure.protocolFailure
        }
        guard reply["ok"] as? Bool == true else { throw SavedSearchDriverFailure.backend }
        return reply
    }
    func configData(_ key: String) throws -> Data? {
        let reply = try request(["method": "get", "key": key])
        if reply["missing"] as? Bool == true { return nil }
        guard let raw = reply["json"] as? String, let data = Data(base64Encoded: raw) else {
            throw SavedSearchDriverFailure.protocolFailure
        }
        return data
    }
    func setConfigValue(_ key: String, value: Any) throws {
        _ = try request(["method": "set", "key": key, "value": value])
    }
}

@main struct SavedSearchDriver {
    static func main() async throws {
        let engine = Engine()
        while let line = readLine() {
            let value = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
            do {
                let searches: [String: String]
                switch value["operation"] as! String {
                case "save": searches = try await engine.saveBrowserSearch(name: value["name"] as! String, query: value["query"] as! String)
                case "remove": searches = try await engine.removeBrowserSearches(value["names"] as! [String])
                case "parallel":
                    let successes = await withTaskGroup(of: Bool.self) { group in
                        for _ in 0..<2 {
                            group.addTask {
                                do {
                                    _ = try await engine.saveBrowserSearch(name: "Concurrent", query: "row")
                                    return true
                                } catch { return false }
                            }
                        }
                        var count = 0
                        for await success in group { if success { count += 1 } }
                        return count
                    }
                    try sendSavedSearchMessage(["done": true, "successes": successes])
                    continue
                case "get": searches = try await engine.browserSavedSearches()
                default: throw SavedSearchDriverFailure.protocolFailure
                }
                try sendSavedSearchMessage(["done": true, "searches": searches])
            } catch let error as BrowserSavedSearchFailure {
                try sendSavedSearchMessage(["done": true, "error": String(describing: error)])
            } catch { try sendSavedSearchMessage(["done": true, "error": "backend"]) }
        }
    }
}
