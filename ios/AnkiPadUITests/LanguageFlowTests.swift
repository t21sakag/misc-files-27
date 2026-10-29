import XCTest

final class LanguageFlowTests: StudyFlowTestSupport {
    func testLanguageSavesOnRelaunchAndKeepsNoteTextWithTranslatedKeys() {
        let app = makeApplication(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30))
        app.buttons["add-note"].tap()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20), app.debugDescription)
        front.tap(); front.typeText("保存")
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["note-close"].tap()

        func settings(_ title: String) {
            XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
            app.buttons["collection-menu"].tap(); app.buttons[title].tap()
            XCTAssertTrue(app.collectionViews["settings-form"].waitForExistence(timeout: 20), app.debugDescription)
        }
        func choose(_ title: String) {
            let picker = app.buttons["app-language"]
            revealSettingsControl(picker, in: app)
            picker.tap(); app.buttons[title].firstMatch.tap()
        }
        settings("設定"); choose("English")
        app.buttons["settings-cancel"].tap()
        settings("設定")
        XCTAssertTrue(app.buttons["app-language"].label.contains("日本語"), app.debugDescription)
        choose("English"); app.buttons["settings-save"].tap()
        // Saving changes the next launch, not the current engine or screen.
        settings("設定")
        XCTAssertTrue(app.navigationBars["設定"].exists)
        XCTAssertTrue(app.buttons["app-language"].label.contains("English"), app.debugDescription)
        app.buttons["settings-cancel"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30))
        settings("Settings")
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        XCTAssertTrue(app.buttons["settings-save"].label == "Save", app.debugDescription)
        XCTAssertTrue(app.buttons["app-language"].label.contains("English"), app.debugDescription)
        choose("日本語"); app.buttons["settings-cancel"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30))

        app.buttons["collection-menu"].tap(); app.buttons["browser-open"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(search.placeholderValue?.hasPrefix("Search (") == true, app.debugDescription)
        search.tap(); search.typeText("保存")
        XCTAssertTrue(app.staticTexts["保存"].waitForExistence(timeout: 30), "User note text must remain Japanese: " + app.debugDescription)
        let count = app.staticTexts["browser-results"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS[c] %@ AND label CONTAINS[c] %@", "Cards: 1", "Selected: 0"), object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed, app.debugDescription)
        app.buttons["Close"].firstMatch.tap()
        app.buttons["collection-menu"].tap(); app.buttons["statistics"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Today"].waitForExistence(timeout: 60), "Backend language must also be English: " + app.debugDescription)
        app.buttons["backend-close"].tap()

        settings("Settings"); choose("日本語"); app.buttons["settings-save"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30))
        settings("設定")
        XCTAssertTrue(app.buttons["settings-save"].label == "保存", app.debugDescription)
        app.buttons["settings-cancel"].tap()
    }
}
