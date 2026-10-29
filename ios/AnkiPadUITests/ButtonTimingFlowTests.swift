import XCTest

final class ButtonTimingFlowTests: StudyFlowTestSupport {
    func testRevealHoldPersistsCancelsOutsideAndAcceptsSustainedPress() {
        let app = makeApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["add-note"].waitForExistence(timeout: 30)); app.buttons["add-note"].tap()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20)); front.tap(); front.typeText("Button hold timing verification")
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30)); app.buttons["note-close"].tap()
        let deck = app.buttons["deck-1"], reveal = app.buttons["reveal"], good = app.buttons["answer-2"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
        XCTAssertTrue(reveal.waitForExistence(timeout: 30)); reveal.tap()
        XCTAssertTrue(good.waitForExistence(timeout: 20), "Default remains a normal tap")
        app.buttons["デッキ"].tap()
        func settings() {
            app.buttons["collection-menu"].tap(); app.buttons["設定"].tap()
        }
        func enter(_ id: String, _ value: String) {
            let field = app.textFields[id]
            revealSettingsControl(field, in: app)
            // LabeledContent exposes the whole row as the text-field frame.
            // Its center is the label; the actual numeric input is on the right.
            let frame = field.frame, origin = app.frame.origin
            app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                .withOffset(CGVector(dx: frame.maxX - 12 - origin.x, dy: frame.midY - origin.y)).doubleTap()
            let selectAll = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Select All", "すべてを選択", "全てを選択"])).firstMatch
            if selectAll.waitForExistence(timeout: 3) { selectAll.tap() }
            field.typeText(value)
            XCTAssertEqual(field.value as? String, value)
        }
        settings()
        enter("answer-hold-time", "2001")
        app.buttons["settings-save"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 20))
        app.alerts.buttons["閉じる"].tap()
        enter("answer-hold-time", "650")
        enter("review-button-interval", "330")
        app.buttons["settings-save"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForNonExistence(timeout: 30))
        app.terminate(); app.launch()
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
        XCTAssertTrue(reveal.waitForExistence(timeout: 30)); reveal.tap()
        XCTAssertFalse(good.exists); XCTAssertTrue(reveal.exists)
        reveal.press(forDuration: 0.2)
        XCTAssertFalse(good.exists); XCTAssertTrue(reveal.exists)
        reveal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)), withVelocity: .fast, thenHoldForDuration: 0.8)
        XCTAssertFalse(good.exists, "Leaving the button must cancel the pending hold")
        reveal.press(forDuration: 0.9)
        XCTAssertTrue(good.waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["デッキ"].tap(); settings()
        let hold = app.textFields["answer-hold-time"], interval = app.textFields["review-button-interval"]
        revealSettingsControl(hold, in: app); XCTAssertEqual(hold.value as? String, "650")
        revealSettingsControl(interval, in: app); XCTAssertEqual(interval.value as? String, "330")
        app.navigationBars["設定"].buttons["キャンセル"].tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
