import XCTest

class TypographyTestSupport: StudyFlowTestSupport {
    func application() -> XCUIApplication {
        let app = makeApplication()
        app.launchArguments = []
        app.launch()
        _ = waitForTestControl(app.buttons.matching(identifier: "add-note"), in: app)
        return app
    }

    func capture(_ title: String, in app: XCUIApplication) {
        XCTContext.runActivity(named: title) { activity in
            let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screen.name = title
            screen.lifetime = .keepAlways
            activity.add(screen)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = title + " hierarchy"
            hierarchy.lifetime = .keepAlways
            activity.add(hierarchy)
        }
    }

    func addNote(front: String, back: String? = nil, in app: XCUIApplication) throws {
        tapTestControl(app.buttons.matching(identifier: "add-note"), in: app)
        let form = app.collectionViews["note-form"]
        try XCTUnwrap(typeInEmptyTestField(app.textViews.matching(identifier: "note-field-0"), text: front, in: app, form: form))
        if let back {
            try XCTUnwrap(typeInEmptyTestField(app.textViews.matching(identifier: "note-field-1"), text: back, in: app, form: form))
        }
        tapTestControl(app.buttons.matching(identifier: "note-save"), in: app)
        _ = waitForTestControl(app.staticTexts.matching(identifier: "note-added"), in: app, purpose: .observation)
        tapTestControl(app.buttons.matching(identifier: "note-close"), in: app)
    }

    func openBrowser(_ app: XCUIApplication) {
        tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-open"), in: app)
    }

}
