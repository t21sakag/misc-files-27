import XCTest

final class AnswerLayoutFlowTests: StudyFlowTestSupport {
    func testAnswerLayoutPersistsWithTopLargeButtonsAndHiddenMode() {
        let app = makeApplication()
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
        let reveal = app.buttons["reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 30))
        let originalHeight = reveal.frame.height
        app.buttons["デッキ"].tap()
        func settings() {
            app.buttons["collection-menu"].tap(); app.buttons["設定"].tap()
            let position = app.buttons["answer-position"]
            let form = app.collectionViews["settings-form"]
            for _ in 0..<14 {
                if position.exists && position.isHittable { break }
                form.swipeUp()
            }
            waitUntilHittable(position)
        }
        settings()
        app.buttons["answer-position"].tap(); app.buttons["上"].firstMatch.tap()
        let outer = app.switches["answer-large"]
        XCTAssertTrue(outer.waitForExistence(timeout: 20))
        let toggle = outer.switches.firstMatch.exists ? outer.switches.firstMatch : outer
        waitUntilHittable(toggle)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        let form = app.collectionViews["settings-form"]
        let size = app.sliders["answer-size"]
        for _ in 0..<12 {
            let targetY = size.exists ? size.frame.midY : CGFloat.greatestFiniteMagnitude
            let upper = form.frame.minY + 160, lower = form.frame.maxY - 100
            if size.exists && targetY >= upper && targetY <= lower { break }
            let upward = !size.exists || targetY > lower
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.65 : 0.35))
                .press(forDuration: 0.1, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.45 : 0.55)), withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        waitUntilHittable(size)
        let value = Double(size.value as? String ?? "100") ?? 100
        let thumb = 0.03 + 0.94 * (value - 10) / 190
        size.coordinate(withNormalizedOffset: CGVector(dx: thumb, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: size.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(app.staticTexts["ボタンの大きさ: 200%"].exists, app.debugDescription)
        app.buttons["settings-save"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForNonExistence(timeout: 30), app.debugDescription)
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
        XCTAssertTrue(reveal.waitForExistence(timeout: 30))
        XCTAssertGreaterThan(reveal.frame.height, originalHeight)
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 30))
        XCTAssertLessThanOrEqual(reveal.frame.maxY, web.frame.minY + 2)
        reveal.tap()
        let again = app.buttons["answer-0"], hard = app.buttons["answer-1"]
        let good = app.buttons["answer-2"], easy = app.buttons["answer-3"]
        XCTAssertTrue(good.waitForExistence(timeout: 20))
        XCTAssertLessThan(hard.frame.midY, again.frame.midY)
        XCTAssertLessThan(easy.frame.midY, good.frame.midY)
        XCTAssertLessThan(hard.frame.midX, easy.frame.midX)
        XCTAssertLessThan(again.frame.midX, good.frame.midX)
        XCTAssertLessThanOrEqual(good.frame.maxY, web.frame.minY + 2)
        app.buttons["デッキ"].tap()
        settings()
        app.buttons["answer-position"].tap(); app.buttons["表示しない"].firstMatch.tap()
        app.buttons["settings-save"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForNonExistence(timeout: 30), app.debugDescription)
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
        XCTAssertTrue(app.webViews.staticTexts["AnkiDroid API metadata verified"].waitForExistence(timeout: 30))
        XCTAssertFalse(reveal.exists)
        XCTAssertFalse(good.exists)
        XCTAssertTrue(app.buttons["reviewer-menu"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
