import XCTest

final class ShareExtensionFlowTests: StudyFlowTestSupport {
    func testSafariSharePersistsUntilExplicitNoteSaveAndDoesNotReopenAfterCancel() {
        let app = makeApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        defer { if safari.state != .notRunning { safari.terminate() } }
        let url = URL(string: "http://127.0.0.1:18892/share-note")!
        XCUIDevice.shared.system.open(url)
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 20))
        for title in ["Continue", "続ける", "Not Now", "今はしない"] {
            let button = safari.buttons[title].firstMatch
            if button.waitForExistence(timeout: 2) && button.isHittable {
                tapTestControl(safari.buttons.matching(NSPredicate(format: "label == %@", title)), in: safari, keyboard: .keep)
            }
        }
        tapTestControl(safari.buttons.matching(identifier: "ShareButton"), in: safari)
        openTestShareService(in: safari)
        let content = safari.textViews["share-text"]
        XCTAssertTrue(content.waitForExistence(timeout: 20), safari.debugDescription)
        XCTAssertTrue((content.value as? String ?? "").contains(url.absoluteString), safari.debugDescription)
        completeTestShare(in: safari, subject: "Safari shared sentinel")
        // A completed extension has only published a durable request. It does
        // not launch the containing app or write a note into its collection.
        app.activate()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertEqual(front.value as? String, "Safari shared sentinel")
        let back = app.textViews["note-field-1"]
        XCTAssertTrue(dismissTestKeyboard(in: app))
        revealFormControl(back, in: app.collectionViews["note-form"], topInset: 40, bottomInset: 20)
        XCTAssertTrue((back.value as? String ?? "").contains(url.absoluteString), app.debugDescription)
        tapTestControl(app.buttons.matching(identifier: "note-close"), in: app)
        let discard = app.buttons["破棄"].firstMatch
        if discard.waitForExistence(timeout: 3) {
            tapTestControl(app.buttons.matching(NSPredicate(format: "label == %@", "破棄")), in: app)
        }
        XCTAssertTrue(front.waitForNonExistence(timeout: 15))
        assertBrowserContains(app, text: "Safari shared sentinel", exists: false)
        let inbox = app.buttons["shared-inbox-open"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 15), app.debugDescription)
        tapTestControl(app.buttons.matching(identifier: "shared-inbox-open"), in: app)
        let reopen = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "shared-inbox-open-")).firstMatch
        XCTAssertTrue(reopen.waitForExistence(timeout: 15), app.debugDescription)
        tapTestControl(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "shared-inbox-open-")), in: app)
        XCTAssertTrue(front.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertEqual(front.value as? String, "Safari shared sentinel")
        tapTestControl(app.buttons.matching(identifier: "note-save"), in: app)
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30), app.debugDescription)
        tapTestControl(app.buttons.matching(identifier: "note-close"), in: app)
        XCTAssertTrue(inbox.waitForNonExistence(timeout: 15), app.debugDescription)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
        XCTAssertFalse(front.exists, app.debugDescription)
        XCTAssertFalse(inbox.exists, app.debugDescription)
        assertBrowserContains(app, text: "Safari shared sentinel", exists: true)
    }
    func testPhotoShareSurvivesConfirmationCancelAndRelaunchBeforeSavingMedia() {
        let app = makeApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
        let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        defer { if photos.state != .notRunning { photos.terminate() } }
        prepareTestPhotoLibrary(photos)
        tapTestControl(photos.buttons.matching(NSPredicate(format: "label IN %@", ["Share", "共有"])), in: photos)
        openTestShareService(in: photos)
        XCTAssertTrue(photos.staticTexts["share-file-0"].waitForExistence(timeout: 20), photos.debugDescription)
        completeTestShare(in: photos, subject: "Shared picture sentinel")
        app.activate()
        let cancel = app.buttons["incoming-import-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 30), app.debugDescription)
        tapTestControl(app.buttons.matching(identifier: "incoming-import-cancel"), in: app)
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 15))
        let inbox = app.buttons["shared-inbox-open"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 15), app.debugDescription)
        // No provider or Photos process is alive when the durable file is read
        // again. Cancelling the confirmation did not consume it.
        photos.terminate(); app.terminate(); app.launch()
        tapTestControl(app.buttons.matching(identifier: "incoming-image-note"), in: app, form: app.collectionViews["incoming-import-form"])
        let editor = app.images["image-editor-image"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), app.debugDescription)
        let dimensions = (editor.value as? String ?? "").components(separatedBy: "×").compactMap { Int($0.filter(\.isNumber)) }
        XCTAssertEqual(dimensions, [512, 384], app.debugDescription)
        tapTestControl(app.buttons.matching(identifier: "image-editor-insert"), in: app)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 20))
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20), app.debugDescription)
        let html = front.value as? String ?? ""
        XCTAssertTrue(html.contains("Shared picture sentinel") && html.contains("<img"), html)
        tapTestControl(app.buttons.matching(identifier: "note-save"), in: app)
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30), app.debugDescription)
        tapTestControl(app.buttons.matching(identifier: "note-close"), in: app)
        XCTAssertTrue(inbox.waitForNonExistence(timeout: 15), app.debugDescription)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertFalse(inbox.exists, app.debugDescription)
        assertBrowserContains(app, text: "Shared picture sentinel", exists: true)
        tapTestControl(app.buttons.matching(identifier: "deck-1"), in: app)
        XCTAssertTrue(app.webViews.images.firstMatch.waitForExistence(timeout: 30), app.debugDescription)
    }

}
