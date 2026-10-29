import Foundation

struct SyncDecision {
    let required: String
    let endpoint: String?
    let message: String
    let serverUSN: Int
    let localCardCount: Int
    let localDeckCount: Int
    init(response: [String: Any], localCardCount: Int, localDeckCount: Int) {
        required = response["required"] as? String ?? "NO_CHANGES"
        endpoint = response["newEndpoint"] as? String
        message = response["serverMessage"] as? String ?? ""
        serverUSN = response["serverMediaUsn"] as? Int ?? 0
        self.localCardCount = localCardCount
        self.localDeckCount = localDeckCount
    }
    var needsFull: Bool { ["FULL_SYNC", "FULL_DOWNLOAD", "FULL_UPLOAD"].contains(required) }
    var canUpload: Bool { localCardCount > 0 && ["FULL_SYNC", "FULL_UPLOAD"].contains(required) }
    var canDownload: Bool { ["FULL_SYNC", "FULL_DOWNLOAD"].contains(required) }
    var automaticallyDownload: Bool { needsFull && localCardCount == 0 && canDownload }
    var localSummary: String { AppText.localized("このiPad: デッキ \(localDeckCount)個・カード \(localCardCount)枚") }
}
