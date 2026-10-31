import XCTest

final class TypingFocusFlowTests: StudyFlowTestSupport {
    func testTypedAnswerAutoFocusCanBeDisabledAndManualInputStillWorks() {
        let app = makeApplication(); app.launchArguments = []; app.launch()
        tapTestControl(app.buttons.matching(identifier: "add-note"), in: app)
        tapTestControl(app.buttons.matching(identifier: "note-type"), in: app)
        tapTestMenuAction(titles: ["基本 (解答を入力)"], in: app)
        let form = app.collectionViews["note-form"]
        guard let front = tapTestControl(app.textViews.matching(identifier: "note-field-0"), in: app, form: form) else { return }
        front.typeText("""
        Typing focus verification<div id="typing-focus-status" aria-live="polite"></div><script>(()=>{function report(){document.getElementById('typing-focus-status').textContent=document.activeElement?.id==='typeans'?'Typing input focused':'Typing input not focused';}document.addEventListener('focusin',report);document.addEventListener('focusout',()=>setTimeout(report,0));window.addEventListener('load',()=>setTimeout(report,500));})();</script>
        """)
        // Keyboard existence alone includes offscreen nodes after it closes.
        guard dismissTestKeyboard(in: app) else { return }
        guard let back = tapTestControl(app.textViews.matching(identifier: "note-field-1"), in: app, form: form) else { return }
        back.typeText("typed expected")
        tapTestControl(app.buttons.matching(identifier: "note-save"), in: app)
        guard waitForTestControl(app.staticTexts.matching(identifier: "note-added"), in: app, purpose: .observation) != nil else { return }
        tapTestControl(app.buttons.matching(identifier: "note-close"), in: app)
        let inputQuery = app.webViews.textFields.matching(NSPredicate(format: "label == %@", "解答を入力"))
        func observeFocus(_ focused: Bool) -> XCUIElement? {
            // Observing auto-focus must not dismiss its keyboard or tap the input.
            guard let input = waitForTestControl(inputQuery, in: app, keyboard: .keep) else { return nil }
            let title = focused ? "Typing input focused" : "Typing input not focused"
            guard waitForTestControl(app.webViews.staticTexts.matching(NSPredicate(format: "label == %@", title)), in: app,
                                     keyboard: .keep, purpose: .observation) != nil else { return nil }
            return input
        }
        func verifyAnswer() {
            tapTestControl(app.buttons.matching(identifier: "reveal"), in: app)
            guard waitForTestControl(app.buttons.matching(identifier: "answer-2"), in: app) != nil else { return }
            // Comparison and Back can both contain the answer. This is a
            // visible-content assertion over the set, not an arbitrary first read.
            requireTestCondition("Rendered answer contains typed expected", in: app) {
                app.webViews.staticTexts.matching(NSPredicate(format: "label == %@", "typed expected"))
                    .allElementsBoundByIndex.contains { $0.isHittable }
            }
        }
        tapTestControl(app.buttons.matching(identifier: "deck-1"), in: app)
        guard let focused = observeFocus(true) else { return }
        focused.typeText("typed expected")
        requireTestCondition("Auto-focused input received the full answer", in: app) { focused.value as? String == "typed expected" }
        verifyAnswer()
        tapTestControl(app.navigationBars.buttons.matching(NSPredicate(format: "label == %@", "デッキ")), in: app)
        tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        tapTestMenuAction(titles: ["設定"], in: app)
        let options = app.switches.matching(identifier: "auto-focus-type-answer")
        revealSettingsControl(options.element, in: app)
        guard let enabled = waitForTestControl(options, in: app, purpose: .observation) else { return }
        XCTAssertEqual(enabled.value as? String, "1", "Auto-focus defaults to on")
        setTestSwitch(options, enabled: false, in: app)
        tapTestControl(app.buttons.matching(identifier: "settings-save"), in: app)
        requireTestCondition("Settings dismissed after save", in: app) { !app.navigationBars["設定"].exists }
        app.terminate(); app.launch()
        tapTestControl(app.buttons.matching(identifier: "deck-1"), in: app)
        guard observeFocus(false) != nil else { return }
        guard let manual = tapTestControl(inputQuery, in: app, keyboard: .keep) else { return }
        manual.typeText("typed expected")
        requireTestCondition("Manual input received the full answer", in: app) { manual.value as? String == "typed expected" }
        verifyAnswer()
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
