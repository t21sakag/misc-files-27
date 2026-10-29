import XCTest

final class ConditionalReminderFlowTests: StudyFlowTestSupport {
    func testConditionalDueThresholdCreatesDatedRequestsAndPreservesLegacyRepeatingMode() {
        let app = makeApplication()
        app.launchArguments += ["--uitest-reminders"]
        app.launch()
        func open() {
            XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
            app.buttons["collection-menu"].tap(); app.buttons["設定"].tap()
            let link = app.buttons["reminder-open"]
            revealSettingsControl(link, in: app); link.tap()
            XCTAssertTrue(app.collectionViews["reminder-form"].waitForExistence(timeout: 20))
        }
        func reveal(_ item: XCUIElement) {
            let form = app.collectionViews["reminder-form"]
            for _ in 0..<20 {
                if item.exists && item.isHittable && item.frame.minY > form.frame.minY + 150 && item.frame.maxY < form.frame.maxY - 8 { return }
                let upward = !item.exists || item.frame.maxY >= form.frame.maxY - 8
                form.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: upward ? 0.65 : 0.35))
                    .press(forDuration: 0.1, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: upward ? 0.45 : 0.55)), withVelocity: .slow, thenHoldForDuration: 0.2)
            }
            XCTFail(app.debugDescription)
        }
        let minimum = app.steppers["reminder-minimum-due"]
        func changeMinimum(_ increment: Bool) {
            reveal(minimum)
            let button = minimum.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", increment ? "-Increment" : "-Decrement")).firstMatch
            XCTAssertTrue(button.exists, app.debugDescription); button.tap()
        }
        func save(authorize: Bool = false) {
            let button = app.buttons["reminder-save"]
            reveal(button); button.tap()
            if authorize {
                let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "許可"])).firstMatch
                if allow.waitForExistence(timeout: 10) { allow.tap() }
            }
            XCTAssertTrue(app.navigationBars["学習リマインダー"].waitForNonExistence(timeout: 30), reminderFailureContext(app))
            app.buttons["settings-save"].tap()
            XCTAssertTrue(app.navigationBars["設定"].waitForNonExistence(timeout: 30))
        }
        func records() -> [[String: Any]] {
            let state = app.staticTexts["reminder-native-schedule"]
            reveal(state)
            let data = (state.value as? String ?? "").data(using: .utf8)!
            let result = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            let records = result["pending"] as! [[String: Any]]
            XCTAssertEqual(Set(records.compactMap { $0["id"] as? String }), Set(result["savedIDs"] as! [String]))
            return records
        }
        open()
        let outer = app.switches["reminder-enabled"]
        XCTAssertTrue(outer.waitForExistence(timeout: 20))
        let toggle = outer.switches.firstMatch.exists ? outer.switches.firstMatch : outer
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        changeMinimum(true)
        save(authorize: true)
        app.terminate(); app.launchArguments = ["--uitest-reminders"]; app.launch()
        open()
        let dated = records()
        XCTAssertFalse(dated.isEmpty)
        XCTAssertLessThanOrEqual(dated.count, 14)
        XCTAssertTrue(dated.allSatisfy { $0["repeats"] as? Bool == false && ($0["year"] as? Int ?? 0) > 2020 })
        changeMinimum(true) // One synthetic due card cannot meet a threshold of two.
        save()
        open(); XCTAssertTrue(records().isEmpty, app.debugDescription)
        changeMinimum(false); changeMinimum(false)
        save()
        open()
        let repeating = records()
        XCTAssertEqual(repeating.count, 7)
        XCTAssertTrue(repeating.allSatisfy { $0["repeats"] as? Bool == true })
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
