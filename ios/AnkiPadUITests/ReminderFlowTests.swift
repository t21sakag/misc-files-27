import XCTest

final class ReminderFlowTests: StudyFlowTestSupport {
    func testReminderNativeSchedulePersistsReplacesAndCancels() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture", "--uitest-reminders"]
        app.launch()
        func openSettings() {
            let menu = app.buttons["collection-menu"]
            XCTAssertTrue(menu.waitForExistence(timeout: 30))
            menu.tap(); app.buttons["設定"].tap()
        }
        func openReminder() {
            let link = app.buttons["reminder-open"]
            let form = app.collectionViews["settings-form"]
            XCTAssertTrue(form.waitForExistence(timeout: 20))
            for _ in 0..<16 {
                if link.exists && link.isHittable { break }
                form.swipeUp()
            }
            waitUntilHittable(link)
            link.tap()
            XCTAssertTrue(app.collectionViews["reminder-form"].waitForExistence(timeout: 20))
        }
        func control(_ id: String) -> XCUIElement {
            let outer = app.switches[id]
            return outer.switches.firstMatch.exists ? outer.switches.firstMatch : outer
        }
        func setSwitch(_ id: String, _ enabled: Bool, upward: Bool = true) {
            let form = app.collectionViews["reminder-form"]
            for _ in 0..<12 {
                if control(id).exists && control(id).isHittable { break }
                if upward { form.swipeUp() } else { form.swipeDown() }
            }
            let item = control(id)
            waitUntilHittable(item)
            if item.value as? String != (enabled ? "1" : "0") { item.tap() }
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", enabled ? "1" : "0"), object: control(id))
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed, id + " " + app.debugDescription)
        }
        func save(authorize: Bool = false) {
            let button = app.buttons["reminder-save"]
            for _ in 0..<10 {
                if button.exists && button.isHittable { break }
                app.collectionViews["reminder-form"].swipeUp()
            }
            waitUntilHittable(button)
            button.tap()
            if authorize {
                let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
                let allow = system.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "許可"])).firstMatch
                if allow.waitForExistence(timeout: 8) { allow.tap() }
            }
            XCTAssertTrue(app.navigationBars["学習リマインダー"].waitForNonExistence(timeout: 30), app.debugDescription)
        }
        func snapshot(days: Set<Int>) -> Set<String> {
            let status = app.staticTexts["reminder-native-schedule"]
            for _ in 0..<10 {
                if status.exists && status.isHittable { break }
                app.collectionViews["reminder-form"].swipeUp()
            }
            XCTAssertTrue(status.waitForExistence(timeout: 20), app.debugDescription)
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard status.exists, let value = status.value as? String, let data = value.data(using: .utf8),
                      let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let pending = result["pending"] as? [[String: Any]] else { return false }
                return pending.count == days.count && Set(pending.compactMap { $0["weekday"] as? Int }) == days
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, app.debugDescription)
            guard let data = (status.value as? String)?.data(using: .utf8),
                  let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let pending = result["pending"] as? [[String: Any]],
                  let saved = result["savedIDs"] as? [String] else { XCTFail("Missing actual OS schedule"); return [] }
            for request in pending {
                XCTAssertEqual(request["profileID"] as? String, "default")
                XCTAssertEqual(request["hour"] as? Int, 19)
                XCTAssertEqual(request["minute"] as? Int, 0)
                XCTAssertEqual(request["repeats"] as? Bool, true)
                XCTAssertEqual(request["sound"] as? Bool, false)
            }
            let ids = Set(pending.compactMap { $0["id"] as? String })
            XCTAssertEqual(ids, Set(saved), "Persisted IDs must match requests in the OS")
            return ids
        }
        openSettings(); openReminder()
        setSwitch("reminder-enabled", true, upward: false)
        setSwitch("reminder-sound", false, upward: false)
        for day in 3...7 { setSwitch("reminder-weekday-\(day)", false) }
        save(authorize: true)
        openReminder()
        let first = snapshot(days: [1, 2])
        XCTAssertEqual(first.count, 2)
        app.terminate(); app.launchArguments = ["--uitest-reminders"]; app.launch()
        openSettings(); openReminder()
        XCTAssertEqual(snapshot(days: [1, 2]), first)
        setSwitch("reminder-enabled", true, upward: false)
        setSwitch("reminder-weekday-1", false)
        save()
        openReminder()
        let replacement = snapshot(days: [2])
        XCTAssertTrue(replacement.isDisjoint(with: first), "Old batch must be removed when replacing a schedule")
        // Invalid enabled settings preserve the previous OS batch.
        setSwitch("reminder-weekday-2", false, upward: false)
        let saveButton = app.buttons["reminder-save"]
        for _ in 0..<10 { if saveButton.isHittable { break }; app.collectionViews["reminder-form"].swipeUp() }
        saveButton.tap()
        XCTAssertTrue(app.alerts["保存できませんでした"].waitForExistence(timeout: 20))
        app.alerts.buttons["閉じる"].tap()
        XCTAssertEqual(snapshot(days: [2]), replacement, "Rejected settings must preserve the existing OS schedule")
        setSwitch("reminder-enabled", false, upward: false)
        save() // Disabling must work even with no selected weekdays.
        openReminder()
        XCTAssertTrue(snapshot(days: []).isEmpty)
        for _ in 0..<10 {
            if control("reminder-enabled").exists && control("reminder-enabled").isHittable { break }
            app.collectionViews["reminder-form"].swipeDown()
        }
        XCTAssertEqual(control("reminder-enabled").value as? String, "0")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
