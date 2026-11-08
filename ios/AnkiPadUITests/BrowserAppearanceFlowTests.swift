import XCTest

final class BrowserAppearanceFlowTests: TypographyTestSupport {
    func testBrowserFontAndSoundNamesPersistAfterRelaunch() throws {
        let app = application()
        try addNote(front: "Browser display literal.mp3 [sound:clip.mp3] <img src=\"photo.png\">", in: app)
        openBrowser(app)
        let fronts = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-front-"))
        let front = try XCTUnwrap(waitForTestControl(fronts, in: app, purpose: .observation))
        XCTAssertTrue(front.label.contains("literal.mp3"))
        XCTAssertTrue(front.label.contains("photo.png"))
        XCTAssertFalse(front.label.contains("clip.mp3"))
        let originalHeight = front.frame.height
        capture("Browser default reading size", in: app)
        tapTestControl(app.navigationBars.buttons.matching(NSPredicate(format: "label == %@", "閉じる")), in: app)
        tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        tapTestMenuAction(titles: ["設定"], in: app)
        _ = try XCTUnwrap(waitForTestControl(app.scrollViews.matching(identifier: "settings-form"), in: app, purpose: .observation))
        let sizes = app.steppers.matching(identifier: "browser-font-size")
        revealSettingsControl(sizes.element, in: app)
        let size = try XCTUnwrap(waitForTestControl(sizes, in: app, purpose: .observation))
        XCTAssertTrue(size.label.contains("100%"))
        capture("Browser font stepper before increment", in: app)
        let increment = sizes.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "-Increment"))
        tapTestControl(increment, in: app)
        tapTestControl(increment, in: app)
        requireTestCondition("Browser font preference reaches120percent", in: app) { size.label.contains("120%") }
        let filenameSwitch = app.switches.matching(identifier: "browser-media-filenames")
        revealSettingsControl(filenameSwitch.element, in: app)
        _ = waitForTestControl(filenameSwitch, in: app, purpose: .observation)
        capture("Before browser display preference switch", in: app)
        setTestSwitch(filenameSwitch, enabled: true, in: app)
        tapTestControl(app.buttons.matching(identifier: "settings-save"), in: app)
        requireTestCondition("Display settings saved and closed", in: app) { app.buttons.matching(identifier: "settings-save").count == 0 }
        app.terminate()
        app.launch()
        openBrowser(app)
        let restored = try XCTUnwrap(waitForTestControl(fronts, in: app, purpose: .observation))
        XCTAssertTrue(restored.label.contains("clip.mp3"))
        XCTAssertTrue(restored.label.contains("literal.mp3"))
        XCTAssertTrue(restored.label.contains("photo.png"))
        XCTAssertGreaterThan(restored.frame.height, originalHeight + 2)
        capture("User browser percentage retained after relaunch", in: app)
        XCTAssertEqual(app.alerts.count, 0)
    }
}
