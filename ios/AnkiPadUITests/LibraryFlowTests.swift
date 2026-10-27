import XCTest

final class LibraryFlowTests: StudyFlowTestSupport {
    func testSubdeckCollapsePersistsAndParentReviewsChildren() {
        let app = makeApplication()
        app.launch()
        let menu = app.buttons["collection-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.tap()
        app.buttons["デッキを作成"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 20))
        name.tap(); name.typeText("Hierarchy Parent::Nested Child")
        app.alerts.buttons["保存"].tap()
        let toggle = app.buttons["Hierarchy Parentを展開"]
        let collapse = app.buttons["Hierarchy Parentを折りたたむ"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20) || collapse.exists)
        if toggle.exists { toggle.tap() }
        let child = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'deck-' AND label BEGINSWITH 'Nested Child,'")).firstMatch
        XCTAssertTrue(child.waitForExistence(timeout: 20))
        child.press(forDuration: 1)
        app.buttons["ノートを追加"].tap()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20))
        front.tap(); front.typeText("Nested review question")
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30))
        app.buttons["note-close"].tap()
        XCTAssertTrue(collapse.waitForExistence(timeout: 20))
        collapse.tap()
        XCTAssertTrue(child.waitForNonExistence(timeout: 20))
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(toggle.waitForExistence(timeout: 30))
        XCTAssertFalse(child.exists)
        // Search can find a hidden child without changing persisted disclosure.
        let search = app.searchFields["デッキを検索"]
        search.tap(); search.typeText("Nested Child")
        XCTAssertTrue(child.waitForExistence(timeout: 20))
        search.buttons.firstMatch.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        XCTAssertFalse(child.exists)
        let parent = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'deck-' AND label BEGINSWITH 'Hierarchy Parent,'")).firstMatch
        XCTAssertTrue(parent.label.contains("1"), "Parent must count its child's new card")
        parent.tap()
        XCTAssertTrue(app.webViews.staticTexts["Nested review question"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.buttons["reveal"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testStoredBackupCanBeSharedToFiles() {
        let app = makeApplication()
        let profile = prepareSyncProfile(app, name: "Backup share check")
        openMaintenance(app)
        let filename = createStoredBackup(app)
        app.buttons["backup-share-" + filename].tap()
        let save = app.cells["Save to Files"].firstMatch
        if !save.waitForExistence(timeout: 10) { app.swipeUp() }
        XCTAssertTrue(save.waitForExistence(timeout: 20), app.debugDescription)
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 20), app.debugDescription)
        close.tap()
        XCTAssertTrue(app.buttons["backup-share-" + filename].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["backup-restore-" + filename].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.buttons["maintenance-close"].tap()
        removeSyncProfile(app, id: profile)
    }

    func testStoredBackupRestoresAndPreservesCurrentCollection() {
        let app = makeApplication()
        let profile = prepareSyncProfile(app, name: "Backup restore check", withFixture: false)
        addUnsyncedNote(app, frontText: "Backup original")
        openMaintenance(app)
        let original = createStoredBackup(app)
        app.buttons["maintenance-close"].tap()
        waitForSyncIdle(app)
        addUnsyncedNote(app, frontText: "Backup newer")
        openMaintenance(app)
        app.buttons["backup-restore-" + original].tap()
        let restore = app.buttons["backup-confirm-restore"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 20))
        restore.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["バックアップを復元しました"].waitForExistence(timeout: 40), app.debugDescription)
        let recovery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@", "backup-restore-", "backup-restore-" + original)).firstMatch
        XCTAssertTrue(recovery.waitForExistence(timeout: 20), "Restoring must preserve the pre-restore collection")
        let recoveryID = recovery.identifier
        app.buttons["maintenance-close"].tap()
        waitForSyncIdle(app)
        assertBrowserContains(app, text: "Backup original", exists: true)
        assertBrowserContains(app, text: "Backup newer", exists: false)
        openMaintenance(app)
        app.buttons[recoveryID].tap()
        app.buttons["backup-confirm-restore"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["バックアップを復元しました"].waitForExistence(timeout: 40), app.debugDescription)
        app.buttons["maintenance-close"].tap()
        waitForSyncIdle(app)
        assertBrowserContains(app, text: "Backup newer", exists: true)
        removeSyncProfile(app, id: profile)
    }

    func testNoteCanBeCreatedAndFoundInBrowser() {
        let app = makeApplication()
        app.launch()
        let add = app.buttons["add-note"]
        XCTAssertTrue(add.waitForExistence(timeout: 30))
        add.tap()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20), app.debugDescription)
        front.tap()
        front.typeText("Created on iPad")
        XCTAssertTrue((front.value as? String ?? "").contains("Created on iPad"), app.debugDescription)
        let back = app.textViews["note-field-1"]
        for _ in 0..<8 {
            if back.exists && back.isHittable { break }
            app.collectionViews["note-form"].swipeUp()
        }
        XCTAssertTrue(back.waitForExistence(timeout: 15), app.debugDescription)
        back.tap()
        back.typeText("Edited with native engine")
        XCTAssertTrue((back.value as? String ?? "").contains("Edited with native engine"), app.debugDescription)
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["note-close"].tap()
        let menu = app.buttons["collection-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30), app.debugDescription)
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["browser-open"].tap()
        let search = app.searchFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", "検索（")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        search.typeText("Created on iPad")
        XCTAssertTrue(app.staticTexts["Created on iPad"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testStatisticsUseRealBundledInterface() {
        let app = makeApplication()
        app.launch()
        let menu = app.buttons["collection-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["statistics"].tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.webViews.staticTexts["今日"].waitForExistence(timeout: 60), app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "iPad-statistics"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testNoteTypesCanBeCreatedAndRenamed() {
        let app = makeApplication()
        app.launch()
        let menu = app.buttons["collection-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["notetypes"].tap()
        let add = app.buttons["notetype-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 20))
        add.tap()
        let name = app.textFields["notetype-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 20))
        name.tap()
        name.typeText("UI test schema")
        app.buttons["notetype-create"].tap()
        let created = app.buttons["UI test schema"]
        XCTAssertTrue(created.waitForExistence(timeout: 30), app.debugDescription)
        created.tap()
        let editName = app.textFields["notetype-edit-name"]
        XCTAssertTrue(editName.waitForExistence(timeout: 30), app.debugDescription)
        editName.tap()
        editName.typeText(" changed")
        app.buttons["notetype-save"].tap()
        XCTAssertTrue(app.buttons["UI test schema changed"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testDeckOptionsUseBundledInterface() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.press(forDuration: 1)
        app.buttons["デッキオプション"].tap()
        XCTAssertTrue(app.webViews.staticTexts["FSRS"].waitForExistence(timeout: 60), app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "iPad-deck-options"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testZZSharedDeckCanBeDownloadedAndImported() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture", "--uitest-shared-decks"]
        app.launch()
        let menu = app.buttons["collection-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["shared-decks"].tap()
        let details = app.webViews.links["View fixture deck"]
        XCTAssertTrue(details.waitForExistence(timeout: 90), app.debugDescription)
        details.tap()
        let back = app.buttons["shared-browser-back"]
        let backReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: back)
        XCTAssertEqual(XCTWaiter.wait(for: [backReady], timeout: 20), .completed)
        back.tap()
        XCTAssertTrue(details.waitForExistence(timeout: 30), app.debugDescription)
        details.tap()
        let link = app.webViews.links["Download fixture deck"]
        XCTAssertTrue(link.waitForExistence(timeout: 30), app.debugDescription)
        link.tap()
        let confirm = app.buttons.matching(identifier: "shared-deck-import").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 30), app.debugDescription)
        confirm.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let deck = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Shared fixture,")).firstMatch
        XCTAssertTrue(deck.waitForExistence(timeout: 40), app.debugDescription)
        deck.tap()
        XCTAssertTrue(app.webViews.staticTexts["Shared deck fixture"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.buttons["reveal"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

}
