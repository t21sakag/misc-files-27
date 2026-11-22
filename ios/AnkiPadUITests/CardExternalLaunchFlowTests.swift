import XCTest

final class CardExternalLaunchFlowTests: StudyFlowTestSupport {
    func testCardAppLinkIsDeniedByDefaultAndOpensAfterSavedPermission() {
        let app = makeApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["add-note"].waitForExistence(timeout: 30))
        app.buttons["add-note"].tap()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20)); front.tap()
        front.typeText("""
        <a href="app-settings:">Open fixture app settings</a><div id="media-context"></div><script>window.addEventListener('load',()=>{document.getElementById('media-context').textContent='Media context: secure='+isSecureContext+', capture='+typeof navigator.mediaDevices?.getUserMedia;});</script>
        """)
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30)); app.buttons["note-close"].tap()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
        let link = app.webViews.links["Open fixture app settings"]
        XCTAssertTrue(link.waitForExistence(timeout: 30))
        let context = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Media context:'")).firstMatch
        XCTAssertTrue(context.waitForExistence(timeout: 20))
        print("Card recording capability observation: " + context.label)
        link.tap()
        let denied = app.staticTexts["card-script-toast"]
        XCTAssertTrue(denied.waitForExistence(timeout: 20))
        XCTAssertTrue(denied.label.contains("許可されていません"))
        XCTAssertEqual(app.state, .runningForeground)
        app.buttons["デッキ"].tap()
        app.buttons["collection-menu"].tap(); app.buttons["設定"].tap()
        let outer = app.switches.matching(identifier: "allow-card-external-launch")
        revealSettingsControl(outer.firstMatch, in: app)
        let toggle = outer.children(matching: .switch).count > 0 ? outer.children(matching: .switch) : outer
        guard let initial = waitForTestControl(toggle, in: app, purpose: .observation) else { return }
        XCTAssertEqual(initial.value as? String, "0")
        XCTAssertTrue(setTestSwitch(outer, enabled: true, in: app))
        app.buttons["settings-save"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForNonExistence(timeout: 30))
        app.terminate(); app.launch()
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
        XCTAssertTrue(link.waitForExistence(timeout: 30)); link.tap()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 30), app.debugDescription)
        app.activate()
        XCTAssertTrue(app.buttons["reveal"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
