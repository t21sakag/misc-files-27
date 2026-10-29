import XCTest

final class MotionFlowTests: StudyFlowTestSupport {
    func testMotionSettingPersistsCancelsAndControlsNativePresentation() {
        let app = makeApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["add-note"].waitForExistence(timeout: 30)); app.buttons["add-note"].tap()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20)); front.tap()
        front.typeText("""
        <button style="min-height:48px;padding:12px" id="motion-dialog">Check motion dialog</button><div id="motion-result" aria-live="polite"></div><script>document.getElementById('motion-dialog').onclick=()=>{alert('Motion transition check');document.getElementById('motion-result').textContent='Motion dialog returned';};</script>
        """)
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30)); app.buttons["note-close"].tap()
        let probe = app.otherElements["motion-transaction"]
        func observation(_ fragment: String) {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND value CONTAINS %@", fragment), object: probe)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed, app.debugDescription)
        }
        func settings() {
            XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
            app.buttons["collection-menu"].tap(); app.buttons["設定"].tap()
        }
        func animationToggle() -> XCUIElement {
            let outer = app.switches["remove-app-animations"]
            revealSettingsControl(outer, in: app)
            return outer.switches.firstMatch.exists ? outer.switches.firstMatch : outer
        }
        func setReduced(_ reduced: Bool) {
            let toggle = animationToggle()
            if (toggle.value as? String == "1") != reduced { tapScreenFrame(toggle, in: app) }
            XCTAssertEqual(toggle.value as? String, reduced ? "1" : "0")
        }
        func save() {
            app.buttons["settings-save"].tap()
            XCTAssertTrue(app.navigationBars["設定"].waitForNonExistence(timeout: 30))
        }
        func checkDialog(animated: Bool) {
            app.buttons["deck-1"].tap()
            let button = app.webViews.buttons["Check motion dialog"]
            XCTAssertTrue(button.waitForExistence(timeout: 30)); tapScreenFrame(button, in: app)
            XCTAssertTrue(app.alerts.staticTexts["Motion transition check"].waitForExistence(timeout: 20))
            app.alerts.buttons["OK"].tap()
            XCTAssertTrue(app.webViews.staticTexts["Motion dialog returned"].waitForExistence(timeout: 20))
            observation("presentation=" + (animated ? "animated" : "none"))
            app.buttons["デッキ"].tap()
        }
        // System Reduce Motion is observed, never overridden by this test.
        observation("system=normal")
        observation("transaction=normal")
        checkDialog(animated: true)
        settings(); setReduced(true)
        app.navigationBars["設定"].buttons["キャンセル"].tap()
        observation("transaction=normal")
        settings(); XCTAssertEqual(animationToggle().value as? String, "0", "Cancelling must not save")
        setReduced(true); save()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30))
        observation("transaction=disabled;animation=none")
        checkDialog(animated: false)
        settings(); XCTAssertEqual(animationToggle().value as? String, "1", "Saved choice must survive relaunch")
        setReduced(false); save()
        observation("transaction=normal")
        checkDialog(animated: true)
        settings()
        let appearance = app.buttons["app-theme-mode"]
        revealSettingsControl(appearance, in: app); appearance.tap(); app.buttons["ライト"].firstMatch.tap()
        let day = app.buttons["day-theme"]
        revealSettingsControl(day, in: app); day.tap(); app.buttons["E Ink"].tap(); save()
        observation("transaction=disabled;animation=none")
        checkDialog(animated: false)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
