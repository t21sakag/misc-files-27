import XCTest

final class NoteRecordingFlowTests: StudyFlowTestSupport {
    func testRecordedNoteInsertionSurvivesSheetCleanupAndRelaunchWithPlayableMedia() throws {
        let app = makeApplication()
        app.launchArguments = ["--uitest-audio-note"]
        app.launch()
        tapTestControl(app.buttons.matching(identifier: "add-note"), in: app)
        let form = app.collectionViews["note-form"]
        guard let front = tapTestControl(app.textViews.matching(identifier: "note-field-0"), in: app, form: form) else { return }
        let title = "Recorded note survives insert"
        front.typeText(title)
        guard let back = tapTestControl(app.textViews.matching(identifier: "note-field-1"), in: app, form: form) else { return }
        back.typeText("Recorded answer")
        tapTestControl(app.buttons.matching(identifier: "note-attachment-0"), in: app, form: form)
        tapTestMenuAction(titles: ["音声を録音"], in: app)
        tapTestControl(app.buttons.matching(identifier: "note-record-start"), in: app)
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = system.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "許可", "OK"]))
        if allow.element.waitForExistence(timeout: 8) {
            tapTestControl(allow, in: system, keyboard: .keep)
        }
        let durations = app.staticTexts.matching(identifier: "note-record-duration")
        guard let duration = waitForTestControl(durations, in: app, purpose: .observation) else { return }
        requireTestCondition("Actual microphone recording reaches 2.5 seconds", in: app) {
            (Double(duration.value as? String ?? "") ?? 0) >= 2.5
        }
        tapTestControl(app.buttons.matching(identifier: "note-record-stop"), in: app)
        tapTestControl(app.buttons.matching(identifier: "note-record-insert"), in: app)
        requireTestCondition("Recording sheet closes after finalized media insertion", in: app) {
            !app.navigationBars["音声を録音"].exists
        }
        guard let inserted = waitForTestControl(app.textViews.matching(identifier: "note-field-0"), in: app,
                                               form: form, purpose: .observation) else { return }
        let html = try XCTUnwrap(inserted.value as? String)
        let expression = try NSRegularExpression(pattern: #"\[sound:[^\]]+\.m4a\]"#)
        let matches = expression.matches(in: html, range: NSRange(html.startIndex..., in: html))
        guard matches.count == 1 else { XCTFail("Insertion must add exactly one stored audio reference"); return }
        let match = matches[0]
        let markerRange = try XCTUnwrap(Range(match.range, in: html))
        let marker = String(html[markerRange])
        tapTestControl(app.buttons.matching(identifier: "note-save"), in: app)
        guard waitForTestControl(app.staticTexts.matching(identifier: "note-added"), in: app, purpose: .observation) != nil else { return }
        tapTestControl(app.buttons.matching(identifier: "note-close"), in: app)
        app.terminate(); app.launch()
        tapTestControl(app.buttons.matching(identifier: "deck-1"), in: app)
        guard waitForTestControl(app.webViews.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern([title]))),
                                in: app, purpose: .observation) != nil else { return }
        guard let counter = waitForTestControl(app.staticTexts.matching(identifier: "native-audio-completions"), in: app,
                                              purpose: .observation) else { return }
        let before = try XCTUnwrap(Int(counter.value as? String ?? ""))
        let links = app.webViews.links.matching(NSPredicate(format: "label == %@", "音声を再生"))
        guard let replay = waitForTestControl(links, in: app) else { return }
        // Use the shared WebKit frame-based action, preserving unique lookup.
        tapScreenFrame(replay, in: app)
        requireTestCondition("Stored recording actually finishes native playback after relaunch", in: app) {
            (Int(counter.value as? String ?? "") ?? 0) > before
        }
        tapTestControl(app.buttons.matching(identifier: "reviewer-menu"), in: app)
        tapTestMenuAction(titles: ["ノートを編集"], in: app)
        guard let reopened = waitForTestControl(app.textViews.matching(identifier: "note-field-0"), in: app,
                                               form: app.collectionViews["note-form"], purpose: .observation) else { return }
        let persisted = try XCTUnwrap(reopened.value as? String)
        XCTAssertTrue(persisted.contains(marker), "Cleanup and restart must preserve the exact media reference")
        XCTAssertEqual(expression.numberOfMatches(in: persisted, range: NSRange(persisted.startIndex..., in: persisted)), 1)
        XCTAssertFalse(app.alerts.element.exists)
    }
}
