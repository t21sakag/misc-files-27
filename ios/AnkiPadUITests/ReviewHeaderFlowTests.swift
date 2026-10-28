import XCTest

final class ReviewHeaderFlowTests: StudyFlowTestSupport {
    func testReviewTitleAndEstimatePersistAndCanBeHidden() {
        let app = makeApplication()
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        func settings() {
            app.buttons["collection-menu"].tap(); app.buttons["設定"].tap()
            XCTAssertTrue(app.buttons["settings-save"].waitForExistence(timeout: 20))
        }
        func toggle(_ identifier: String, on: Bool) {
            let outer = app.switches[identifier]
            revealSettingsControl(outer, in: app)
            let inner = outer.switches.firstMatch.exists ? outer.switches.firstMatch : outer
            if (inner.value as? String == "1") != on {
                inner.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
            }
            XCTAssertEqual(inner.value as? String, on ? "1" : "0")
        }
        func saveAndRelaunch() {
            app.buttons["settings-save"].tap()
            XCTAssertTrue(app.navigationBars["設定"].waitForNonExistence(timeout: 30))
            app.terminate(); app.launchArguments = []; app.launch()
            XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
            XCTAssertTrue(app.buttons["reveal"].waitForExistence(timeout: 30))
        }
        deck.tap()
        XCTAssertTrue(app.buttons["reveal"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["review-eta"].exists, "ETA defaults to off")
        XCTAssertFalse(app.navigationBars.staticTexts["既定"].exists, "Deck title defaults to off")
        app.buttons["デッキ"].tap()
        settings(); toggle("show-deck-title", on: true); toggle("show-review-eta", on: true)
        saveAndRelaunch()
        XCTAssertTrue(app.navigationBars.staticTexts["既定"].exists, app.debugDescription)
        let eta = app.staticTexts["review-eta"]
        XCTAssertTrue(eta.waitForExistence(timeout: 20))
        let calculated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@", "残り約[0-9]+分"), object: eta)
        XCTAssertEqual(XCTWaiter.wait(for: [calculated], timeout: 20), .completed, app.debugDescription)
        app.buttons["reveal"].tap()
        XCTAssertTrue(app.buttons["answer-2"].waitForExistence(timeout: 20))
        XCTAssertTrue(eta.exists, "Estimate remains visible on the answer side")
        app.buttons["デッキ"].tap()
        settings(); toggle("show-deck-title", on: false); toggle("show-review-eta", on: false)
        saveAndRelaunch()
        XCTAssertFalse(app.staticTexts["review-eta"].exists)
        XCTAssertFalse(app.navigationBars.staticTexts["既定"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
