import Foundation

@main struct SyncDecisionSmoke {
    static func main() {
        for required in ["FULL_SYNC", "FULL_DOWNLOAD", "FULL_UPLOAD"] {
            let empty = SyncDecision(response: ["required": required], localCardCount: 0, localDeckCount: 1)
            precondition(!empty.canUpload, "Empty collections must never upload")
            precondition(empty.automaticallyDownload == (required != "FULL_UPLOAD"))
            let populated = SyncDecision(response: ["required": required], localCardCount: 42, localDeckCount: 3)
            precondition(!populated.automaticallyDownload)
            precondition(populated.canUpload == (required != "FULL_DOWNLOAD"))
            precondition(populated.canDownload == (required != "FULL_UPLOAD"))
            precondition(populated.localSummary.contains("42") && populated.localSummary.contains("3"))
        }
        let unknown = SyncDecision(response: ["required": "UNKNOWN"], localCardCount: 42, localDeckCount: 3)
        precondition(!unknown.canUpload && !unknown.canDownload)
        print("PASS: full sync directions, empty upload denial and local summary")
    }
}
