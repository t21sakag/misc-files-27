import XCTest

final class ConditionalReminderFlowTests: ReminderFlowTestSupport {
    func testConditionalDueThresholdCreatesDatedRequestsAndPreservesLegacyRepeatingMode() throws {
        let app = makeApplication()
        app.launchArguments += ["--uitest-reminders"]
        app.launch()
        openReminderSettings(in: app)
        setReminderSwitch("reminder-enabled", enabled: true, in: app)
        changeReminderMinimum(increment: true, expected: 1, in: app)
        saveReminderSettings(in: app, closeSettings: true)
        app.terminate(); app.launchArguments = ["--uitest-reminders"]; app.launch()
        openReminderSettings(in: app)
        let dated = try readReminderSchedule(in: app).pending
        XCTAssertFalse(dated.isEmpty)
        XCTAssertLessThanOrEqual(dated.count, 14)
        XCTAssertTrue(dated.allSatisfy { $0["repeats"] as? Bool == false && ($0["year"] as? Int ?? 0) > 2020 })
        changeReminderMinimum(increment: true, expected: 2, in: app) // One due card cannot meet two.
        saveReminderSettings(in: app, closeSettings: true)
        openReminderSettings(in: app)
        XCTAssertTrue(try readReminderSchedule(in: app).pending.isEmpty)
        changeReminderMinimum(increment: false, expected: 1, in: app)
        changeReminderMinimum(increment: false, expected: 0, in: app)
        saveReminderSettings(in: app, closeSettings: true)
        openReminderSettings(in: app)
        let repeating = try readReminderSchedule(in: app).pending
        XCTAssertEqual(repeating.count, 7)
        XCTAssertTrue(repeating.allSatisfy { $0["repeats"] as? Bool == true })
        XCTAssertFalse(app.alerts.element.exists)
    }
}
