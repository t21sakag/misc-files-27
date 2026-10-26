import Foundation
import Security

struct SyncCredentials: Codable {
    let username: String
    let hkey: String
    var endpoint: String?
    var request: [String: Any] {
        var result: [String: Any] = ["hkey": hkey, "ioTimeoutSecs": 60]
        if let endpoint { result["endpoint"] = endpoint }
        return result
    }
}
struct SyncDecision {
    let required: String
    let endpoint: String?
    let message: String
    let serverUSN: Int
    init(response: [String: Any]) {
        required = response["required"] as? String ?? "NO_CHANGES"
        endpoint = response["newEndpoint"] as? String
        message = response["serverMessage"] as? String ?? ""
        serverUSN = response["serverMediaUsn"] as? Int ?? 0
    }
    var needsFull: Bool { ["FULL_SYNC", "FULL_DOWNLOAD", "FULL_UPLOAD"].contains(required) }
    var canUpload: Bool { required != "FULL_DOWNLOAD" }
    var canDownload: Bool { required != "FULL_UPLOAD" }
}

enum AccountStore {
    private static let service = "com.localtools.studyclient.ankiweb"
    private static func query(profileID: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: profileID == "default" ? "sync" : "sync." + profileID]
    }
    static func load(profileID: String = "default") throws -> SyncCredentials? {
        var lookup = query(profileID: profileID)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw failure(status) }
        return try JSONDecoder().decode(SyncCredentials.self, from: data)
    }
    static func save(_ account: SyncCredentials, profileID: String = "default") throws {
        let data = try JSONEncoder().encode(account)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query(profileID: profileID) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query(profileID: profileID)
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(insert as CFDictionary, nil)
            guard added == errSecSuccess else { throw failure(added) }
        } else if status != errSecSuccess { throw failure(status) }
    }
    static func delete(profileID: String = "default") throws {
        let status = SecItemDelete(query(profileID: profileID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }
    private static func failure(_ status: OSStatus) -> EngineError {
        EngineError(message: "ログイン情報の保存領域を開けませんでした（\(status)）。")
    }
}
