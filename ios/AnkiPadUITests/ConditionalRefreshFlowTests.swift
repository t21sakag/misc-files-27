import XCTest

final class ConditionalRefreshFlowTests: StudyFlowTestSupport {
    func testScopedReminderRecomputesAfterActualReview() {
        let app = makeApplication()
        app.launchArguments += ["--uitest-reminders"]
        app.launch()
        XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
        app.buttons["collection-menu"].tap(); app.buttons["デッキを作成"].tap()
        let dialog = app.alerts["デッキを作成"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 20))
        dialog.textFields.firstMatch.tap(); dialog.textFields.firstMatch.typeText("Empty reminder scope")
        dialog.buttons["保存"].tap()
        XCTAssertTrue(dialog.waitForNonExistence(timeout: 30))
        let counter = app.staticTexts["reminder-refresh-completions"]
        var beforeSettings = "0"
        func open() {
            XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
            XCTAssertTrue(counter.exists)
            beforeSettings = counter.value as? String ?? "0"
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
            XCTAssertTrue(app.navigationBars["学習リマインダー"].waitForNonExistence(timeout: 30))
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
        func chooseDeck(_ title: String) {
            let picker = app.buttons["reminder-deck"]
            reveal(picker); picker.tap(); app.buttons[title].firstMatch.tap()
        }
        func refreshed(after value: String) {
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", value), object: counter)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 30), .completed, app.debugDescription)
        }
        func closeAfterReading() {
            app.navigationBars["学習リマインダー"].buttons.firstMatch.tap()
            app.navigationBars["設定"].buttons["キャンセル"].tap()
            refreshed(after: beforeSettings)
        }
        open()
        let outer = app.switches["reminder-enabled"]
        XCTAssertTrue(outer.waitForExistence(timeout: 20))
        let toggle = outer.switches.firstMatch.exists ? outer.switches.firstMatch : outer
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        changeMinimum(true)
        chooseDeck("Empty reminder scope")
        save(authorize: true)
        open(); XCTAssertTrue(records().isEmpty, "Cards in other decks must not satisfy this empty scope")
        chooseDeck("すべてのデッキ")
        let noReviews = app.switches["reminder-no-reviews"]
        reveal(noReviews)
        let inner = noReviews.switches.firstMatch.exists ? noReviews.switches.firstMatch : noReviews
        inner.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        save()
        open()
        let initial = records()
        XCTAssertFalse(initial.isEmpty)
        let initialIDs = Set(initial.compactMap { $0["id"] as? String })
        closeAfterReading()
        let beforeSelect = counter.value as? String ?? "0"
        app.buttons["deck-1"].tap(); refreshed(after: beforeSelect)
        let revealButton = app.buttons["reveal"]
        XCTAssertTrue(revealButton.waitForExistence(timeout: 30))
        let beforeReveal = counter.value as? String ?? "0"
        revealButton.tap(); refreshed(after: beforeReveal)
        let good = app.buttons["answer-2"]
        XCTAssertTrue(good.waitForExistence(timeout: 20))
        let beforeAnswer = counter.value as? String ?? "0"
        good.tap(); refreshed(after: beforeAnswer)
        app.buttons["デッキ"].tap()
        open()
        let updated = records()
        XCTAssertFalse(updated.isEmpty, "Future days should retain conditional requests after reviewing today")
        XCTAssertTrue(Set(updated.compactMap { $0["id"] as? String }).isDisjoint(with: initialIDs))
        XCTAssertTrue(updated.allSatisfy { $0["repeats"] as? Bool == false })
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
