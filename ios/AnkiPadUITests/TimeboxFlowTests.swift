import XCTest

final class TimeboxFlowTests: StudyFlowTestSupport {
    func testTimeboxReportsRealElapsedMinuteAndCanContinueOrFinish() {
        let app = makeApplication()
        app.launch()
        XCTAssertTrue(app.buttons["add-note"].waitForExistence(timeout: 30))
        app.buttons["add-note"].tap()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20))
        front.tap(); front.typeText("Second timebox card")
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30))
        app.buttons["note-close"].tap()
        app.buttons["collection-menu"].tap(); app.buttons["設定"].tap()
        let limit = app.steppers["timebox-limit"]
        let form = app.collectionViews["settings-form"]
        for _ in 0..<8 {
            if limit.exists && limit.isHittable { break }
            form.swipeUp()
        }
        waitUntilHittable(limit)
        limit.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()
        XCTAssertTrue(limit.label.contains("1分"), app.debugDescription)
        app.buttons["settings-save"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
        XCTAssertTrue(app.buttons["reveal"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.alerts["学習の区切り"].exists, "Starting review must start a fresh interval")
        func waitMinuteAndAnswer() {
            let deadline = Date().addingTimeInterval(62)
            let elapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in Date() >= deadline }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [elapsed], timeout: 65), .completed)
            XCTAssertFalse(app.alerts["学習の区切り"].exists, "The reminder is checked after an answer, not during a card")
            app.buttons["reveal"].tap()
            let good = app.buttons["answer-2"]
            XCTAssertTrue(good.waitForExistence(timeout: 20)); good.tap()
            XCTAssertTrue(app.alerts["学習の区切り"].waitForExistence(timeout: 30), app.debugDescription)
            XCTAssertTrue(app.alerts.staticTexts["1分で1枚に回答しました。"].exists, app.debugDescription)
        }
        waitMinuteAndAnswer()
        app.buttons["timebox-continue"].firstMatch.tap()
        XCTAssertTrue(app.buttons["reveal"].waitForExistence(timeout: 20))
        waitMinuteAndAnswer()
        app.buttons["timebox-finish"].firstMatch.tap()
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()
        XCTAssertFalse(app.alerts["学習の区切り"].exists, "Reopening a deck must not reuse the old interval")
    }
}
