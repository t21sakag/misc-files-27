import XCTest

final class TypingFocusFlowTests: StudyFlowTestSupport {
    func testTypedAnswerAutoFocusCanBeDisabledAndManualInputStillWorks() {
        let app = makeApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["add-note"].waitForExistence(timeout: 30))
        app.buttons["add-note"].tap()
        let type = app.buttons["note-type"]
        XCTAssertTrue(type.waitForExistence(timeout: 20)); type.tap()
        app.buttons["基本 (解答を入力)"].tap()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20)); front.tap()
        front.typeText("""
        Typing focus verification<div id="typing-focus-status" aria-live="polite"></div><script>(()=>{function report(){document.getElementById('typing-focus-status').textContent=document.activeElement?.id==='typeans'?'Typing input focused':'Typing input not focused';}document.addEventListener('focusin',report);document.addEventListener('focusout',()=>setTimeout(report,0));window.addEventListener('load',()=>setTimeout(report,500));})();</script>
        """)
        let back = app.textViews["note-field-1"]
        let hideKeyboard = app.buttons["Hide keyboard"]
        if hideKeyboard.exists { hideKeyboard.tap() }
        let form = app.collectionViews["note-form"]
        for _ in 0..<12 {
            if back.exists && back.isHittable && back.frame.maxY < form.frame.maxY - 10 { break }
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.7))
                .press(forDuration: 0.1, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.4)), withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(back.exists && back.isHittable, app.debugDescription)
        back.tap(); back.typeText("typed expected")
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30)); app.buttons["note-close"].tap()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
        let input = app.webViews.textFields["解答を入力"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        XCTAssertTrue(app.webViews.staticTexts["Typing input focused"].waitForExistence(timeout: 20), app.debugDescription)
        input.typeText("typed expected")
        app.buttons["reveal"].tap()
        XCTAssertTrue(app.buttons["answer-2"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.webViews.staticTexts["typed expected"].firstMatch.exists, app.debugDescription)
        app.buttons["デッキ"].tap()
        app.buttons["collection-menu"].tap(); app.buttons["設定"].tap()
        let outer = app.switches["auto-focus-type-answer"]
        revealSettingsControl(outer, in: app)
        let toggle = outer.switches.firstMatch.exists ? outer.switches.firstMatch : outer
        XCTAssertEqual(toggle.value as? String, "1", "Auto-focus defaults to on")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["settings-save"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForNonExistence(timeout: 30))
        app.terminate(); app.launch()
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        XCTAssertTrue(app.webViews.staticTexts["Typing input not focused"].waitForExistence(timeout: 20), app.debugDescription)
        input.tap(); input.typeText("typed expected")
        app.buttons["reveal"].tap()
        XCTAssertTrue(app.buttons["answer-2"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.webViews.staticTexts["typed expected"].firstMatch.exists, app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
