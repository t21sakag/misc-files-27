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
    func testNewNoteTypeSwitchRetainsExtraFieldAndBlocksPrematureSave() {
        let app = makeApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
        app.buttons["collection-menu"].tap(); app.buttons["notetypes"].tap()
        func create(_ name: String) {
            XCTAssertTrue(app.buttons["notetype-add"].waitForExistence(timeout: 20))
            app.buttons["notetype-add"].tap()
            let field = app.textFields["notetype-name"]
            XCTAssertTrue(field.waitForExistence(timeout: 20)); field.tap(); field.typeText(name)
            app.buttons["notetype-create"].tap()
            XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 30), app.debugDescription)
        }
        create("Guard Wide")
        app.buttons["Guard Wide"].tap()
        let addField = app.buttons["フィールドを追加"]
        XCTAssertTrue(addField.waitForExistence(timeout: 20)); waitUntilHittable(addField); addField.tap()
        let fieldName = app.alerts.textFields.firstMatch
        XCTAssertTrue(fieldName.waitForExistence(timeout: 10)); fieldName.tap(); fieldName.typeText("Extra")
        app.alerts.buttons["追加"].tap()
        app.buttons["notetype-save"].tap()
        XCTAssertTrue(app.buttons["Guard Wide"].waitForExistence(timeout: 30), app.debugDescription)
        create("Guard Narrow")
        app.navigationBars["ノートタイプ"].buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["add-note"].waitForExistence(timeout: 30)); app.buttons["add-note"].tap()
        let form = app.collectionViews["note-form"]
        func choose(_ type: String) {
            let picker = app.buttons["note-type"]
            revealFormControl(picker, in: form, topInset: 40, bottomInset: 20, searchUpward: false)
            picker.tap(); app.buttons[type].firstMatch.tap()
        }
        func field(_ index: Int) -> XCUIElement {
            let value = app.textViews["note-field-\(index)"]
            revealFormControl(value, in: form, topInset: 40, bottomInset: 20)
            return value
        }
        choose("Guard Wide")
        let front = field(0); front.tap(); front.typeText("Guard front")
        let back = field(1); back.tap(); back.typeText("Guard back")
        let extra = field(2); extra.tap(); extra.typeText("GuardExtraSentinel")
        choose("Guard Narrow")
        let unmapped = app.textViews["note-unmapped-field-2"]
        revealFormControl(unmapped, in: form, topInset: 40, bottomInset: 20)
        XCTAssertEqual(unmapped.value as? String, "GuardExtraSentinel")
        XCTAssertFalse(app.buttons["note-save"].isEnabled, "Unmapped nonempty fields must prevent saving")
        choose("Guard Wide")
        XCTAssertEqual(field(0).value as? String, "Guard front")
        XCTAssertEqual(field(1).value as? String, "Guard back")
        XCTAssertEqual(field(2).value as? String, "GuardExtraSentinel")
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["note-save"])
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 20), .completed, app.debugDescription)
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["note-close"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
        assertBrowserContains(app, text: "GuardExtraSentinel", exists: true)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

}
