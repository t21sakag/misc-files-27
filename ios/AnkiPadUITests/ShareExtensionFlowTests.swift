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
            if button.waitForExistence(timeout: 2) && button.isHittable { button.tap() }
        }
        let share = safari.buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", "ShareButton", ["Share", "共有"])).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 20), safari.debugDescription)
        share.tap()
        let service = safari.cells.matching(NSPredicate(format: "label == %@", "AnkiPad")).firstMatch
        if !service.waitForExistence(timeout: 5) {
            let more = safari.cells.matching(NSPredicate(format: "label IN %@", ["More", "その他"])).firstMatch
            XCTAssertTrue(more.waitForExistence(timeout: 10), safari.debugDescription)
            more.tap()
        }
        XCTAssertTrue(service.waitForExistence(timeout: 15), safari.debugDescription)
        service.tap()
        let subject = safari.textFields["share-subject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 20), safari.debugDescription)
        let content = safari.textViews["share-text"]
        XCTAssertTrue(content.waitForExistence(timeout: 20), safari.debugDescription)
        XCTAssertTrue((content.value as? String ?? "").contains(url.absoluteString), safari.debugDescription)
        subject.tap()
        let old = subject.value as? String ?? ""
        subject.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)+"Safari shared sentinel")
        let send = safari.buttons["share-submit"]
        waitUntilHittable(send); send.tap()
        let complete = safari.buttons["share-complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 20), safari.debugDescription)
        complete.tap()
        // A completed extension has only published a durable request. It does
        // not launch the containing app or write a note into its collection.
        app.activate()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertEqual(front.value as? String, "Safari shared sentinel")
        let back = app.textViews["note-field-1"]
        revealFormControl(back, in: app.collectionViews["note-form"], topInset: 40, bottomInset: 20)
        XCTAssertTrue((back.value as? String ?? "").contains(url.absoluteString), app.debugDescription)
        app.buttons["note-close"].tap()
        let discard = app.buttons["破棄"].firstMatch
        if discard.waitForExistence(timeout: 3) { discard.tap() }
        XCTAssertTrue(front.waitForNonExistence(timeout: 15))
        assertBrowserContains(app, text: "Safari shared sentinel", exists: false)
        let inbox = app.buttons["shared-inbox-open"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 15), app.debugDescription)
        inbox.tap()
        let reopen = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "shared-inbox-open-")).firstMatch
        XCTAssertTrue(reopen.waitForExistence(timeout: 15), app.debugDescription)
        reopen.tap()
        XCTAssertTrue(front.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertEqual(front.value as? String, "Safari shared sentinel")
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["note-close"].tap()
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
        photos.launch()
        // Photos publishes its What's New sheet after the library grid is
        // already in the AX tree. Wait for this known first-launch overlay.
        let welcome = photos.buttons["Continue"].firstMatch
        if welcome.waitForExistence(timeout: 15) {
            waitUntilHittable(welcome); welcome.tap()
            XCTAssertTrue(welcome.waitForNonExistence(timeout: 15), photos.debugDescription)
        }
        let images = photos.images.matching(identifier: "PXGGridLayout-Info")
        XCTAssertTrue(images.firstMatch.waitForExistence(timeout: 25), photos.debugDescription)
        // All Photos is chronological; the imported synthetic image is last.
        // Current-year labels omit the year, so do not parse their display text.
        let image = images.element(boundBy: images.count-1)
        image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let share = photos.buttons.matching(NSPredicate(format: "label IN %@", ["Share", "共有"])).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 15), photos.debugDescription)
        share.tap()
        let service = photos.cells.matching(NSPredicate(format: "label == %@", "AnkiPad")).firstMatch
        XCTAssertTrue(service.waitForExistence(timeout: 20), photos.debugDescription)
        service.tap()
        XCTAssertTrue(photos.staticTexts["share-file-0"].waitForExistence(timeout: 20), photos.debugDescription)
        let subject = photos.textFields["share-subject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 20), photos.debugDescription)
        subject.tap()
        let old = subject.value as? String ?? ""
        subject.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)+"Shared picture sentinel")
        let send = photos.buttons["share-submit"]
        waitUntilHittable(send); send.tap()
        let complete = photos.buttons["share-complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 20), photos.debugDescription)
        complete.tap()
        app.activate()
        let cancel = app.buttons["incoming-import-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 30), app.debugDescription)
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 15))
        let inbox = app.buttons["shared-inbox-open"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 15), app.debugDescription)
        // No provider or Photos process is alive when the durable file is read
        // again. Cancelling the confirmation did not consume it.
        photos.terminate(); app.terminate(); app.launch()
        let attach = app.buttons["incoming-image-note"]
        revealFormControl(attach, in: app.collectionViews["incoming-import-form"], topInset: 40, bottomInset: 20)
        attach.tap()
        let editor = app.images["image-editor-image"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), app.debugDescription)
        let dimensions = (editor.value as? String ?? "").components(separatedBy: "×").compactMap { Int($0.filter(\.isNumber)) }
        XCTAssertEqual(dimensions, [512, 384], app.debugDescription)
        app.buttons["image-editor-insert"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 20))
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20), app.debugDescription)
        let html = front.value as? String ?? ""
        XCTAssertTrue(html.contains("Shared picture sentinel") && html.contains("<img"), html)
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["note-close"].tap()
        XCTAssertTrue(inbox.waitForNonExistence(timeout: 15), app.debugDescription)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertFalse(inbox.exists, app.debugDescription)
        assertBrowserContains(app, text: "Shared picture sentinel", exists: true)
        app.buttons["deck-1"].tap()
        XCTAssertTrue(app.webViews.images.firstMatch.waitForExistence(timeout: 30), app.debugDescription)
    }

}
