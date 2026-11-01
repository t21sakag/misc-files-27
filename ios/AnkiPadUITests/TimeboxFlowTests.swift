import XCTest

final class TimeboxFlowTests: StudyFlowTestSupport {
    func testTimeboxReportsRealElapsedMinuteAndCanContinueOrFinish() {
        let app = makeApplication()
        app.launchArguments += ["--uitest-presentation-trace"]
        app.launch()
        tapTestControl(app.buttons.matching(identifier: "add-note"), in: app)
        typeInEmptyTestField(app.textViews.matching(identifier: "note-field-0"), text: "Second timebox card", in: app,
                             form: app.collectionViews["note-form"])
        tapTestControl(app.buttons.matching(identifier: "note-save"), in: app)
        waitForTestControl(app.staticTexts.matching(identifier: "note-added"), in: app, purpose: .observation)
        tapTestControl(app.buttons.matching(identifier: "note-close"), in: app)
        tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        tapTestMenuAction(titles: ["設定"], in: app)
        let limit = app.steppers.matching(identifier: "timebox-limit")
        revealSettingsControl(limit.element, in: app)
        guard let stepper = waitForTestControl(limit, in: app) else { return }
        tapTestControl(stepper.buttons.matching(NSPredicate(format: "identifier ENDSWITH '-Increment'")), in: app)
        requireTestCondition("Timebox setting reaches one minute", in: app) { stepper.label.contains("1分") }
        tapTestControl(app.buttons.matching(identifier: "settings-save"), in: app)
        app.terminate(); app.launchArguments = ["--uitest-presentation-trace"]; app.launch()
        tapTestControl(app.buttons.matching(identifier: "deck-1"), in: app)
        waitForTestControl(app.buttons.matching(identifier: "reveal"), in: app)
        let notice = app.alerts.matching(identifier: "学習の区切り")
        XCTAssertEqual(notice.count, 0, "Starting review must start a fresh interval")
        func waitMinuteAndAnswer() {
            let deadline = Date().addingTimeInterval(62)
            requireTestCondition("Real timebox interval exceeds sixty seconds", in: app, timeout: 65) { Date() >= deadline }
            XCTAssertEqual(notice.count, 0, "The reminder is checked after an answer, not during a card")
            tapTestControl(app.buttons.matching(identifier: "reveal"), in: app)
            tapTestControl(app.buttons.matching(identifier: "answer-2"), in: app)
            waitForTestControl(notice, in: app, purpose: .observation)
            waitForTestControl(notice.staticTexts.matching(identifier: "1分で1枚に回答しました。"), in: app, purpose: .observation)
        }
        waitMinuteAndAnswer()
        tapTestAlertAction("timebox-continue", in: notice, application: app)
        waitForTestControl(app.buttons.matching(identifier: "reveal"), in: app)
        waitMinuteAndAnswer()
        tapTestAlertAction("timebox-finish", in: notice, application: app)
        tapTestControl(app.buttons.matching(identifier: "deck-1"), in: app)
        waitForTestControl(app.buttons.matching(identifier: "reveal"), in: app)
        XCTAssertEqual(notice.count, 0, "Reopening a deck must not reuse the old interval")
    }
}
