import Foundation

struct ReviewReminderConfigurationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ReviewReminderConfiguration: Codable {
    var enabled = false
    var hour = 19
    var minute = 0
    var weekdays = [1, 2, 3, 4, 5, 6, 7]
    var sound = true
    var requestIDs: [String] = []
    func validate() throws {
        guard (0...23).contains(hour), (0...59).contains(minute), (!enabled || !weekdays.isEmpty),
              weekdays.allSatisfy({ (1...7).contains($0) }), Set(weekdays).count == weekdays.count else {
            throw ReviewReminderConfigurationError(message: "通知の時刻または曜日を確認してください。")
        }
    }
}


/// App-wide reservation budget. New requests are staged while old ones remain
/// installed, so replacements need enough temporary headroom as well.
enum ReviewReminderRequestBudget {
    static let maximumPendingRequests = 60
    static func validateStaging(pendingCount: Int, additions: Int) throws {
        guard pendingCount >= 0, additions >= 0,
              additions <= maximumPendingRequests,
              pendingCount <= maximumPendingRequests - additions else {
            throw ReviewReminderConfigurationError(message: "通知の予約枠が足りません。既存の予約は変更していません。ほかのプロファイルの通知を減らしてから、もう一度保存してください。")
        }
    }
}
