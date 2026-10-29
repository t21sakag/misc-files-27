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
    var minimumDue = 0
    var deckID: String?
    var onlyIfNoReviews = false
    var conditional: Bool { minimumDue > 0 || deckID != nil || onlyIfNoReviews }
    init() {}
    private enum CodingKeys: String, CodingKey { case enabled, hour, minute, weekdays, sound, requestIDs, minimumDue, deckID, onlyIfNoReviews }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        hour = try c.decode(Int.self, forKey: .hour)
        minute = try c.decode(Int.self, forKey: .minute)
        weekdays = try c.decode([Int].self, forKey: .weekdays)
        sound = try c.decode(Bool.self, forKey: .sound)
        requestIDs = try c.decode([String].self, forKey: .requestIDs)
        minimumDue = try c.decodeIfPresent(Int.self, forKey: .minimumDue) ?? 0
        deckID = try c.decodeIfPresent(String.self, forKey: .deckID)
        onlyIfNoReviews = try c.decodeIfPresent(Bool.self, forKey: .onlyIfNoReviews) ?? false
    }
    func validate() throws {
        guard (0...100000).contains(minimumDue), deckID == nil || (Int64(deckID!) ?? 0) > 0 else {
            throw ReviewReminderConfigurationError(message: AppText.localized("通知の枚数と対象デッキを確認してください。"))
        }

        guard (0...23).contains(hour), (0...59).contains(minute), (!enabled || !weekdays.isEmpty),
              weekdays.allSatisfy({ (1...7).contains($0) }), Set(weekdays).count == weekdays.count else {
            throw ReviewReminderConfigurationError(message: AppText.localized("通知の時刻または曜日を確認してください。"))
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
            throw ReviewReminderConfigurationError(message: AppText.localized("通知の予約枠が足りません。既存の予約は変更していません。ほかのプロファイルの通知を減らしてから、もう一度保存してください。"))
        }
    }
}

struct ReviewReminderForecast {
    let date: Date
    let dueCount: Int?
    let reviewed: Bool
    func matches(_ config: ReviewReminderConfiguration) -> Bool {
        guard let dueCount else { return false }
        return dueCount >= config.minimumDue && (!config.onlyIfNoReviews || !reviewed)
    }
}
enum ReviewReminderDates {
    static func upcoming(_ config: ReviewReminderConfiguration, now: Date, calendar: Calendar = .current) -> [Date] {
        (0..<14).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  config.weekdays.contains(calendar.component(.weekday, from: day)),
                  let date = calendar.date(bySettingHour: config.hour, minute: config.minute, second: 0, of: day), date > now else { return nil }
            return date
        }
    }
}
