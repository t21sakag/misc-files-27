import XCTest

final class IncomingFlowTests: StudyFlowTestSupport {
    private func browser(_ app: XCUIApplication, search: String, hasResults: Bool = true) {
        let results = app.staticTexts["browser-results"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND value == %@", search), object: results)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, app.debugDescription)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-card-")).firstMatch
        if hasResults { XCTAssertTrue(row.waitForExistence(timeout: 20), app.debugDescription) }
        else { XCTAssertTrue(row.waitForNonExistence(timeout: 20), app.debugDescription) }
    }
    private func closeBrowser(_ app: XCUIApplication) {
        app.buttons["閉じる"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["browser-results"].waitForNonExistence(timeout: 20))
    }
    func testBrowserURLSearchAndExplicitEmptyKeepSavedNotes() {
        let app = makeApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["add-note"].waitForExistence(timeout: 30))
        addUnsyncedNote(app, frontText: "Incoming needle 日本語")
        app.open(URL(string: "studyclient://x-callback-url/browser?search=Incoming+needle")!)
        browser(app, search: "Incoming needle")
        closeBrowser(app)
        app.open(URL(string: "studyclient://x-callback-url/browser?search=no-such-incoming-note")!)
        browser(app, search: "no-such-incoming-note", hasResults: false)
        closeBrowser(app)
        app.open(URL(string: "studyclient://x-callback-url/browser?search=")!)
        browser(app, search: "")
        XCTAssertTrue(app.staticTexts["Incoming needle 日本語"].exists, app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testBrowserURLWaitsForUnsavedEditorAndUsesLatestSearch() {
        let app = makeApplication()
        app.launch()
        XCTAssertTrue(app.buttons["add-note"].waitForExistence(timeout: 30))
        app.buttons["add-note"].tap()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20))
        front.tap(); front.typeText("Unsaved incoming sentinel")
        XCUIDevice.shared.system.open(URL(string: "studyclient://x-callback-url/browser?search=obsolete")!)
        XCTAssertTrue(front.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(front.value as? String, "Unsaved incoming sentinel")
        XCTAssertFalse(app.staticTexts["browser-results"].exists)
        XCUIDevice.shared.system.open(URL(string: "studyclient://x-callback-url/browser?search=")!)
        XCTAssertEqual(front.value as? String, "Unsaved incoming sentinel")
        app.buttons["note-close"].tap()
        let discard = app.buttons["破棄"]
        XCTAssertTrue(discard.waitForExistence(timeout: 10)); discard.tap()
        browser(app, search: "")
        closeBrowser(app)
        assertBrowserContains(app, text: "Unsaved incoming sentinel", exists: false)
    }
    func testSharedTextRemainsDraftAndPlainFieldsSaveOnlyExplicitly() {
        let app = makeApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
        app.buttons["collection-menu"].tap(); app.buttons["テキストからノートを追加"].tap()
        let subject = app.textFields["shared-text-subject"], body = app.textViews["shared-text-body"]
        XCTAssertTrue(subject.waitForExistence(timeout: 20))
        subject.tap(); subject.typeText("Incoming subject & <literal>")
        body.tap(); body.typeText("Incoming body\nsecond line")
        app.buttons["shared-text-continue"].tap()
        let front = app.textViews["note-field-0"], back = app.textViews["note-field-1"]
        XCTAssertTrue(front.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertEqual(front.value as? String, "Incoming subject &amp; &lt;literal&gt;")
        revealFormControl(back, in: app.collectionViews["note-form"], topInset: 40, bottomInset: 20)
        XCTAssertEqual(back.value as? String, "Incoming body<br>second line")
        app.buttons["note-close"].tap(); app.buttons["破棄"].tap()
        assertBrowserContains(app, text: "Incoming subject", exists: false)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testTextURLHTMLAndTagsSurviveExplicitSaveAndRelaunch() {
        let app = makeApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
        app.open(URL(string: "studyclient://x-callback-url/addnote?front=%3Cb%3EIncomingURL%3C/b%3E&back=answer&tags=incoming-url&html=1")!)
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertEqual(front.value as? String, "<b>IncomingURL</b>")
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["note-close"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
        app.open(URL(string: "studyclient://x-callback-url/browser?search=tag%3Aincoming-url")!)
        browser(app, search: "tag:incoming-url")
        XCTAssertTrue(app.staticTexts["IncomingURL"].exists, app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
