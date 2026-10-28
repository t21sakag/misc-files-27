import XCTest

final class BrowserAppearanceFlowTests: StudyFlowTestSupport {
    func testBrowserFontAndSoundNamesPersistAfterRelaunch() {
        let app = makeApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["add-note"].waitForExistence(timeout: 30)); app.buttons["add-note"].tap()
        let field = app.textViews["note-field-0"]
        XCTAssertTrue(field.waitForExistence(timeout: 20)); field.tap()
        field.typeText("Browser display literal.mp3 [sound:clip.mp3] <img src=\"photo.png\">")
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30)); app.buttons["note-close"].tap()
        func browser() {
            XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
            app.buttons["collection-menu"].tap(); app.buttons["browser-open"].tap()
        }
        let front = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'browser-front-'")).firstMatch
        browser()
        XCTAssertTrue(front.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(front.label.contains("literal.mp3"))
        XCTAssertTrue(front.label.contains("photo.png"))
        XCTAssertFalse(front.label.contains("clip.mp3"))
        let originalHeight = front.frame.height
        app.navigationBars.buttons["閉じる"].firstMatch.tap()
        app.buttons["collection-menu"].tap(); app.buttons["設定"].tap()
        let size = app.steppers["browser-font-size"]
        revealSettingsControl(size, in: app)
        XCTAssertTrue(size.label.contains("100%"))
        let increment = size.buttons.matching(NSPredicate(format: "identifier ENDSWITH '-Increment'")).firstMatch
        XCTAssertTrue(increment.exists, app.debugDescription)
        increment.tap(); increment.tap()
        XCTAssertTrue(size.label.contains("120%"))
        let outer = app.switches["browser-media-filenames"]
        revealSettingsControl(outer, in: app)
        let toggle = outer.switches.firstMatch.exists ? outer.switches.firstMatch : outer
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["settings-save"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForNonExistence(timeout: 30))
        app.terminate(); app.launch()
        browser()
        XCTAssertTrue(front.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(front.label.contains("clip.mp3"))
        XCTAssertTrue(front.label.contains("literal.mp3"))
        XCTAssertTrue(front.label.contains("photo.png"))
        XCTAssertGreaterThan(front.frame.height, originalHeight + 2, "The short one-line field must actually render with a larger font")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
