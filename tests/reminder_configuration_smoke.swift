import Foundation

@main struct ReminderConfigurationSmoke {
    static func main() throws {
        func rejects(_ config: ReviewReminderConfiguration) -> Bool {
            do { try config.validate(); return false } catch { return true }
        }
        var config = ReviewReminderConfiguration()
        try config.validate()
        config.weekdays = []
        try config.validate() // An empty day selection must not prevent disabling reminders.
        config.enabled = true
        precondition(rejects(config))
        config.weekdays = [1, 7]
        config.hour = 23; config.minute = 59
        config.sound = false; config.requestIDs = ["ankipad.review.default.fixture.1", "ankipad.review.default.fixture.7"]
        try config.validate()
        let restored = try JSONDecoder().decode(ReviewReminderConfiguration.self, from: JSONEncoder().encode(config))
        try restored.validate()
        precondition(restored.enabled && restored.hour == 23 && restored.minute == 59)
        precondition(restored.weekdays == [1, 7] && !restored.sound && restored.requestIDs == config.requestIDs)
        config.weekdays = [1, 1]
        precondition(rejects(config))
        config.weekdays = [0, 8]
        precondition(rejects(config))
        config.weekdays = [2]; config.hour = 24
        precondition(rejects(config))
        config.hour = 0; config.minute = -1
        precondition(rejects(config))
        try ReviewReminderRequestBudget.validateStaging(pendingCount: 53, additions: 7)
        do {
            try ReviewReminderRequestBudget.validateStaging(pendingCount: 54, additions: 7)
            preconditionFailure("Cannot stage a new batch while keeping old requests at the app budget")
        } catch is ReviewReminderConfigurationError {}
        do {
            try ReviewReminderRequestBudget.validateStaging(pendingCount: -1, additions: 1)
            preconditionFailure("Invalid pending counts must not be accepted")
        } catch is ReviewReminderConfigurationError {}
        let legacy = Data(#"{"enabled":true,"hour":19,"minute":0,"weekdays":[1,7],"sound":false,"requestIDs":["legacy-first","legacy-second"]}"#.utf8)
        let oldConfig = try JSONDecoder().decode(ReviewReminderConfiguration.self, from: legacy)
        try oldConfig.validate()
        precondition(oldConfig.enabled && oldConfig.weekdays == [1,7] && oldConfig.requestIDs == ["legacy-first","legacy-second"])
        precondition(oldConfig.minimumDue == 0 && oldConfig.deckID == nil && !oldConfig.onlyIfNoReviews && !oldConfig.conditional)
        var conditions = oldConfig
        conditions.minimumDue = 2
        precondition(conditions.conditional)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        precondition(!ReviewReminderForecast(date: now, dueCount: 1, reviewed: false).matches(conditions))
        precondition(ReviewReminderForecast(date: now, dueCount: 2, reviewed: false).matches(conditions))
        conditions.onlyIfNoReviews = true
        precondition(!ReviewReminderForecast(date: now, dueCount: 3, reviewed: true).matches(conditions))
        precondition(!ReviewReminderForecast(date: now, dueCount: nil, reviewed: false).matches(conditions))
        conditions.weekdays = [1,2,3,4,5,6,7]
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let dates = ReviewReminderDates.upcoming(conditions, now: now, calendar: utc)
        precondition(!dates.isEmpty && dates.count <= 14 && dates.allSatisfy { $0 > now })
        let extended = try JSONDecoder().decode(ReviewReminderConfiguration.self, from: JSONEncoder().encode(conditions))
        precondition(extended.minimumDue == 2 && extended.onlyIfNoReviews)
        print("PASS: reminder disabling with empty days, enabled-day validation and schedule persistence")
    }
}
