import XCTest

final class ReminderFlowTests: ReminderFlowTestSupport {
    func testReminderNativeSchedulePersistsReplacesAndCancels() throws {
        let app = makeApplication()
        app.launchArguments += ["--uitest-reminders"]
        app.launch()
        func snapshot(days: Set<Int>) throws -> Set<String> {
            let schedule = try readReminderSchedule(in: app)
            XCTAssertEqual(schedule.pending.count, days.count)
            XCTAssertEqual(Set(schedule.pending.compactMap { $0["weekday"] as? Int }), days)
            for request in schedule.pending {
                XCTAssertEqual(request["profileID"] as? String, "default")
                XCTAssertEqual(request["hour"] as? Int, 19)
                XCTAssertEqual(request["minute"] as? Int, 0)
                XCTAssertEqual(request["repeats"] as? Bool, true)
                XCTAssertEqual(request["sound"] as? Bool, false)
            }
            return schedule.ids
        }
        openReminderSettings(in: app)
        setReminderSwitch("reminder-enabled", enabled: true, in: app)
        setReminderSwitch("reminder-sound", enabled: false, in: app)
        for day in 3...7 { setReminderSwitch("reminder-weekday-\(day)", enabled: false, in: app) }
        saveReminderSettings(in: app)
        openReminderSettings(in: app)
        let first = try snapshot(days: [1, 2])
        XCTAssertEqual(first.count, 2)
        app.terminate(); app.launchArguments = ["--uitest-reminders"]; app.launch()
        openReminderSettings(in: app)
        XCTAssertEqual(try snapshot(days: [1, 2]), first)
        setReminderSwitch("reminder-enabled", enabled: true, in: app)
        setReminderSwitch("reminder-weekday-1", enabled: false, in: app)
        saveReminderSettings(in: app)
        openReminderSettings(in: app)
        let replacement = try snapshot(days: [2])
        XCTAssertTrue(replacement.isDisjoint(with: first), "Old batch must be removed when replacing a schedule")
        // Invalid enabled settings preserve the previous OS batch.
        setReminderSwitch("reminder-weekday-2", enabled: false, in: app)
        tapTestControl(app.buttons.matching(identifier: "reminder-save"), in: app, form: app.collectionViews["reminder-form"])
        let errors = app.alerts.matching(identifier: "保存できませんでした")
        waitForTestControl(errors, in: app, keyboard: .keep, purpose: .observation)
        tapTestAlertAction(titles: ["閉じる"], in: errors, application: app)
        requireTestCondition("Invalid reminder error dismissed", in: app) { errors.count == 0 }
        XCTAssertEqual(try snapshot(days: [2]), replacement, "Rejected settings must preserve the existing OS schedule")
        setReminderSwitch("reminder-enabled", enabled: false, in: app)
        saveReminderSettings(in: app) // Disabling works even with no selected weekdays.
        openReminderSettings(in: app)
        XCTAssertTrue(try snapshot(days: []).isEmpty)
        let enabled = app.collectionViews["reminder-form"].switches.matching(identifier: "reminder-enabled")
        let outer = try XCTUnwrap(waitForTestControl(enabled, in: app, form: app.collectionViews["reminder-form"], purpose: .observation))
        XCTAssertEqual(outer.value as? String, "0")
        XCTAssertFalse(app.alerts.element.exists)
    }
}
