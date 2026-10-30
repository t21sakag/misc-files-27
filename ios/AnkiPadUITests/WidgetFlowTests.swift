import XCTest

final class WidgetFlowTests: StudyFlowTestSupport {
    private func snapshot(_ app: XCUIApplication) -> [String: Any] {
        let state = app.staticTexts["widget-snapshot-state"]
        var result: [String: Any] = [:]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard state.exists, let raw = state.value as? String, let data = raw.data(using: .utf8),
                  let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  value["selectedProfileID"] as? String == "default",
                  let profiles = value["profiles"] as? [[String: Any]],
                  let primary = profiles.first(where: { $0["id"] as? String == "default" }),
                  primary["collection"] is [String: Any] else { return false }
            result = value; return true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, "Stored widget snapshot: \(String(describing: state.value))\n" + app.debugDescription)
        return result
    }
    private func open(_ app: XCUIApplication, destination: String, deck: String? = nil) {
        let suffix = deck.map { "&deck=" + $0 } ?? ""
        app.open(URL(string: "studyclient://widget/" + destination + "?profile=default" + suffix)!)
    }
    func testWidgetRoutesOpenReviewOptionsAndDraftWithoutSaving() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture", "--uitest-widgets"]
        app.launch()
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30), app.debugDescription)
        let stored = snapshot(app)
        let primary = (stored["profiles"] as! [[String: Any]]).first { $0["id"] as? String == "default" }!
        let collection = primary["collection"] as! [String: Any]
        XCTAssertTrue((collection["decks"] as! [[String: Any]]).contains { $0["id"] as? String == "1" })
        open(app, destination: "review", deck: "1")
        XCTAssertTrue(app.buttons["reveal"].waitForExistence(timeout: 30), app.debugDescription)
        open(app, destination: "home")
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30), app.debugDescription)
        open(app, destination: "options", deck: "1")
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.navigationBars["デッキオプション"].exists)
        tapTestControl(app.buttons.matching(identifier: "backend-close"), in: app)
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30))
        open(app, destination: "add", deck: "1")
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertEqual(front.value as? String, "")
        tapTestControl(app.buttons.matching(identifier: "note-close"), in: app)
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 20))
        app.terminate(); app.launchArguments = ["--uitest-widgets"]; app.launch()
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        _ = snapshot(app)
    }
    func testWidgetRouteWaitsForUnsavedEditorAndRejectsMissingDeck() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture", "--uitest-widgets"]
        app.launch()
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30))
        _ = snapshot(app)
        open(app, destination: "add", deck: "1")
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20))
        tapTestControl(app.textViews.matching(identifier: "note-field-0"), in: app, form: app.collectionViews["note-form"])
        front.typeText("Widget unsaved sentinel")
        XCUIDevice.shared.system.open(URL(string: "studyclient://widget/home?profile=default")!)
        XCTAssertTrue(front.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(front.value as? String, "Widget unsaved sentinel")
        XCUIDevice.shared.system.open(URL(string: "studyclient://widget/review?profile=default&deck=9223372036854775807")!)
        XCTAssertEqual(front.value as? String, "Widget unsaved sentinel")
        tapTestControl(app.buttons.matching(identifier: "note-close"), in: app)
        tapTestControl(app.buttons.matching(identifier: "破棄"), in: app)
        let message = app.alerts.staticTexts["ウィジェットのデッキが見つかりません。ウィジェットを設定し直してください。"]
        XCTAssertTrue(message.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertFalse(app.buttons["reveal"].exists, "Missing widget deck must never review another deck")
        tapTestControl(app.alerts.buttons.matching(identifier: "閉じる"), in: app)
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.textViews["note-field-0"].exists)
    }
}
