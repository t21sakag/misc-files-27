import XCTest

final class StudyFlowTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    func testAnkiDroidCardJavaScriptReadsNativeMetadata() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()
        XCTAssertTrue(app.webViews.staticTexts["AnkiDroid API metadata verified"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.webViews.staticTexts["Embedded frame loaded; native bridge denied"].waitForExistence(timeout: 30), app.debugDescription)
        app.webViews.buttons["API mutations"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.webViews.staticTexts["AnkiDroid API mutations verified"].waitForExistence(timeout: 30), app.debugDescription)
        let menu = app.buttons["reviewer-menu"]
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let actionsMenu = app.buttons["template-actions-menu"]
        XCTAssertTrue(actionsMenu.waitForExistence(timeout: 20), app.debugDescription)
        actionsMenu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["template-action-9"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["template-action-9"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Template action 9 verified"].waitForExistence(timeout: 20), app.debugDescription)
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["template-hint-next"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Template hint revealed"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testAnkiWebLoginAndTokenSurviveRelaunch() {
        let app = XCUIApplication()
        let profile = prepareSyncProfile(app, name: "Empty download safety check", withFixture: false)
        let account = app.buttons["ankiweb-account"]
        XCTAssertTrue(account.waitForExistence(timeout: 30))
        account.tap()
        let username = app.textFields["login-username"]
        XCTAssertTrue(username.waitForExistence(timeout: 20))
        username.tap()
        username.typeText("fixture@example.test")
        let password = app.secureTextFields["login-password"]
        password.tap()
        password.typeText("fixture-password")
        app.switches["custom-server-toggle"].switches.firstMatch.tap()
        let endpoint = app.textFields["custom-server-endpoint"]
        XCTAssertTrue(endpoint.waitForExistence(timeout: 15), app.debugDescription)
        endpoint.tap()
        endpoint.typeText("http://127.0.0.1:18891/")
        app.buttons["login-submit"].tap()
        // An empty local collection must download without offering upload.
        XCTAssertFalse(app.buttons["このiPadのデータをAnkiWebにアップロード"].exists)
        XCTAssertTrue(app.staticTexts["同期しました"].waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertTrue(app.buttons["deck-1"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["fixture@example.test"].waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["ankiweb-account"].tap()
        app.buttons["logout"].tap()
        app.buttons["閉じる"].firstMatch.tap()
        XCTAssertTrue(app.buttons["login-entry"].waitForExistence(timeout: 20))
        removeSyncProfile(app, id: profile)
    }

    private func prepareSyncProfile(_ app: XCUIApplication, name: String, withFixture: Bool = true) -> String {
        app.launch()
        let menu = app.buttons["collection-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["profiles-open"].tap()
        XCTAssertTrue(app.buttons["profile-add"].waitForExistence(timeout: 20))
        app.buttons["profile-add"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap(); field.typeText(name)
        app.alerts.buttons.matching(identifier: "profile-save").firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["login-entry"].waitForExistence(timeout: 30))
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["profiles-open"].tap()
        let profile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "profile-", name)).firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 20))
        let id = profile.identifier
        app.buttons["profiles-close"].tap()
        app.terminate()
        app.launchArguments = withFixture ? ["--uitest-fixture"] : []
        app.launch()
        return id
    }

    private func removeSyncProfile(_ app: XCUIApplication, id: String) {
        func openProfiles() {
            let menu = app.buttons["collection-menu"]
            XCTAssertTrue(menu.waitForExistence(timeout: 30))
            menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            app.buttons["profiles-open"].tap()
            XCTAssertTrue(app.buttons["profile-default"].waitForExistence(timeout: 20))
        }
        openProfiles()
        app.buttons["profile-default"].tap()
        XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
        openProfiles()
        app.buttons[id].press(forDuration: 1)
        app.buttons["削除"].firstMatch.tap()
        let confirm = app.alerts.buttons["削除"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 20))
        confirm.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons[id])
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 20), .completed)
        app.buttons["profiles-close"].tap()
    }

    private func loginToSyncFixture(_ app: XCUIApplication, username value: String) {
        let account = app.buttons["ankiweb-account"]
        XCTAssertTrue(account.waitForExistence(timeout: 30))
        account.tap()
        let username = app.textFields["login-username"]
        XCTAssertTrue(username.waitForExistence(timeout: 20))
        username.tap(); username.typeText(value)
        app.secureTextFields["login-password"].tap()
        app.secureTextFields["login-password"].typeText("fixture-password")
        app.switches["custom-server-toggle"].switches.firstMatch.tap()
        let endpoint = app.textFields["custom-server-endpoint"]
        XCTAssertTrue(endpoint.waitForExistence(timeout: 20))
        endpoint.tap(); endpoint.typeText("http://127.0.0.1:18891/")
        app.buttons["login-submit"].tap()
    }

    func testFullSyncConflictShowsLocalCounts() {
        let app = XCUIApplication()
        let profile = prepareSyncProfile(app, name: "Conflict safety check")
        loginToSyncFixture(app, username: "fixture@example.test")
        let download = app.buttons["AnkiWebのデータをこのiPadにダウンロード"]
        XCTAssertTrue(download.waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertTrue(app.buttons["このiPadのデータをAnkiWebにアップロード"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "このiPad: デッキ 1個・カード 1枚")).firstMatch.exists, app.debugDescription)
        download.tap()
        let replace = app.alerts.buttons["置き換えて同期"]
        XCTAssertTrue(replace.waitForExistence(timeout: 20))
        replace.tap()
        XCTAssertTrue(app.staticTexts["同期しました"].waitForExistence(timeout: 60), app.debugDescription)
        removeSyncProfile(app, id: profile)
    }

    func testFullSyncWithLocalDataRequiresTypedUploadConfirmation() {
        let app = XCUIApplication()
        let profile = prepareSyncProfile(app, name: "Upload safety check")
        loginToSyncFixture(app, username: "empty@example.test")
        let replace = app.alerts.buttons["置き換えて同期"]
        XCTAssertTrue(replace.waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertFalse(replace.isEnabled, "Upload requires explicit typed confirmation")
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "このiPad: デッキ")).firstMatch.exists)
        let confirmation = app.alerts.textFields.firstMatch
        XCTAssertTrue(confirmation.exists)
        confirmation.tap(); confirmation.typeText("アップロード")
        XCTAssertTrue(replace.isEnabled)
        replace.tap()
        XCTAssertTrue(app.staticTexts["同期しました"].waitForExistence(timeout: 60), app.debugDescription)
        app.buttons["ankiweb-account"].tap()
        app.buttons["logout"].tap()
        app.buttons["閉じる"].firstMatch.tap()
        XCTAssertTrue(app.buttons["login-entry"].waitForExistence(timeout: 20))
        removeSyncProfile(app, id: profile)
    }

    func testJavaScriptDialogsReturnNativeInputAndDecisions() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()
        let button = app.webViews.buttons["API dialogs"]
        XCTAssertTrue(button.waitForExistence(timeout: 30))
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let input = app.alerts.textFields["card-js-prompt-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 20), app.debugDescription)
        input.tap(); input.typeText("template input")
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.alerts.staticTexts["Template confirm"].waitForExistence(timeout: 20), app.debugDescription)
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.alerts.staticTexts["Template alert"].waitForExistence(timeout: 20), app.debugDescription)
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Template dialogs verified"].waitForExistence(timeout: 20), app.debugDescription)
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(input.waitForExistence(timeout: 20), app.debugDescription)
        app.alerts.buttons["キャンセル"].tap()
        XCTAssertTrue(app.alerts.staticTexts["Template cancel confirm"].waitForExistence(timeout: 20), app.debugDescription)
        app.alerts.buttons["キャンセル"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Template dialog cancellation verified"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testNavigationAndReviewerOptionsAPIOpenNativePanels() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["AnkiDroid API metadata verified"].waitForExistence(timeout: 30), app.debugDescription)
        web.buttons["API options"].tap()
        let info = app.buttons["review-option-info"]
        XCTAssertTrue(info.waitForExistence(timeout: 20), app.debugDescription)
        info.tap()
        let bar = app.navigationBars["カード情報"]
        XCTAssertTrue(bar.waitForExistence(timeout: 30), app.debugDescription)
        bar.buttons["閉じる"].tap()
        XCTAssertTrue(web.buttons["API navigation"].waitForExistence(timeout: 20))
        web.buttons["API navigation"].tap()
        let decks = app.buttons["destination-decks"]
        XCTAssertTrue(decks.waitForExistence(timeout: 20), app.debugDescription)
        decks.tap()
        XCTAssertTrue(deck.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testReviewVoicePanelClosesWithoutChangingCard() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["AnkiDroid API metadata verified"].waitForExistence(timeout: 30), app.debugDescription)
        let options = web.buttons["API options"]
        XCTAssertTrue(options.waitForExistence(timeout: 30))
        options.tap()
        let voice = app.buttons["review-option-voice"]
        let list = app.collectionViews["reviewer-options-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 20), app.debugDescription)
        for _ in 0..<6 {
            if voice.exists && voice.isHittable { break }
            list.swipeUp()
        }
        XCTAssertTrue(voice.waitForExistence(timeout: 20), app.debugDescription)
        voice.tap()
        let panel = app.navigationBars["自分の声"]
        XCTAssertTrue(panel.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["録音を開始"].exists)
        XCTAssertFalse(app.buttons["録音を再生"].exists)
        panel.buttons["閉じる"].tap()
        XCTAssertTrue(options.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["reveal"].exists)
        XCTAssertTrue(web.staticTexts["AnkiDroid API metadata verified"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testNoteCanBeCreatedAndFoundInBrowser() {
        let app = XCUIApplication()
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
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        search.typeText("Created on iPad")
        XCTAssertTrue(app.staticTexts["Created on iPad"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    private func setCollectionPermission(_ app: XCUIApplication, enabled: Bool) {
        let menu = app.buttons["collection-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["設定"].tap()
        let toggle = app.switches["allow-collection-card-api"]
        for _ in 0..<12 {
            if toggle.exists && toggle.isHittable { break }
            app.collectionViews["settings-form"].swipeUp()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 15), app.debugDescription)
        let control = toggle.switches.firstMatch
        if (control.value as? String == "1") != enabled { control.tap() }
        app.buttons["settings-save"].tap()
    }

    func testUnsafeCollectionAPIRequiresExplicitSetting() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["AnkiDroid API metadata verified"].waitForExistence(timeout: 30), app.debugDescription)
        web.buttons["API collection query"].tap()
        XCTAssertTrue(web.staticTexts["Collection access denied"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["デッキ"].tap()
        setCollectionPermission(app, enabled: true)
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()
        XCTAssertTrue(web.staticTexts["AnkiDroid API metadata verified"].waitForExistence(timeout: 30))
        web.buttons["API collection query"].tap()
        XCTAssertTrue(web.staticTexts["Collection query verified"].waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["デッキ"].tap()
        setCollectionPermission(app, enabled: false)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testStatisticsUseRealBundledInterface() {
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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

    func testAutoAdvancePausesWhileEditing() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()
        let reveal = app.buttons["reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 30))
        reveal.tap()
        XCTAssertTrue(app.buttons["answer-2"].waitForExistence(timeout: 20))
        let menu = app.buttons["reviewer-menu"]
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["auto-advance-toggle"].tap()
        if !app.buttons["ノートを編集"].exists { menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        app.buttons["ノートを編集"].tap()
        let close = app.buttons["note-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 20), app.debugDescription)
        Thread.sleep(forTimeInterval: 9)
        close.tap()
        XCTAssertTrue(app.buttons["answer-2"].waitForExistence(timeout: 20), "The answer changed while its note editor was open. " + app.debugDescription)
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["auto-advance-toggle"].tap()
    }

    func testCustomSchedulingChangesAnswerInterval() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.press(forDuration: 1)
        app.buttons["デッキオプション"].tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 30))
        let custom = web.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "カスタムスケジューリング")).firstMatch
        for _ in 0..<15 { if custom.exists && custom.isHittable { break }; web.swipeUp() }
        XCTAssertTrue(custom.exists, app.debugDescription)
        custom.tap()
        let code = web.textViews.firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 15), app.debugDescription)
        code.tap()
        code.typeText("states.easy.normal.review.scheduledDays = 7;")
        let save = web.buttons["保存"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 15), app.debugDescription)
        save.tap()
        XCTAssertTrue(deck.waitForExistence(timeout: 30), app.debugDescription)
        deck.tap()
        let reveal = app.buttons["reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 30), app.debugDescription)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: reveal)
        waitForExpectations(timeout: 30)
        reveal.tap()
        let easy = app.buttons["answer-3"]
        XCTAssertTrue(easy.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(easy.label.contains("7"), easy.label)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testFullscreenCanBeRestoredWithTripleTap() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let menu = app.buttons["collection-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["設定"].tap()
        let mode = app.buttons["review-display-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 20), app.debugDescription)
        mode.tap()
        app.buttons["カードのみ"].tap()
        app.buttons["settings-save"].tap()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["reveal"].exists)
        web.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        XCTAssertTrue(app.buttons["reveal"].waitForExistence(timeout: 20), app.debugDescription)
    }

    func testImportedDeckCanBeReviewedAndUndone() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertTrue(deck.isEnabled)
        deck.tap()
        let reveal = app.buttons["reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 20))
        app.buttons["whiteboard-toggle"].tap()
        let board = app.scrollViews["whiteboard"]
        XCTAssertTrue(board.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["whiteboard-toggle"].tap()
        reveal.tap()
        let good = app.buttons["answer-2"]
        XCTAssertTrue(good.waitForExistence(timeout: 20), app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "iPad-answer-screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        good.tap()
        let undo = app.buttons["取り消す"]
        XCTAssertTrue(undo.waitForExistence(timeout: 20))
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: undo)
        waitForExpectations(timeout: 20)
        undo.tap()
        XCTAssertTrue(reveal.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.staticTexts["新規 1 · 学習 0 · 復習 0"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
    }
    func testPreviewCardAPIReadsAndRestoresFlag() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let menu = app.buttons["collection-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        setCollectionPermission(app, enabled: false)
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["browser-open"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap(); search.typeText("Rust")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-card-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.press(forDuration: 1)
        app.buttons["プレビュー"].tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["AnkiDroid API metadata verified"].waitForExistence(timeout: 30), app.debugDescription)
        let probe = web.buttons["Preview API check"]
        XCTAssertTrue(probe.waitForExistence(timeout: 30), app.debugDescription)
        probe.tap()
        XCTAssertTrue(web.staticTexts["Preview API verified"].waitForExistence(timeout: 20), app.debugDescription)
        web.buttons["API mutations"].tap()
        XCTAssertTrue(web.staticTexts["AnkiDroid API mutations verified"].waitForExistence(timeout: 20), app.debugDescription)
        web.buttons["API collection query"].tap()
        XCTAssertTrue(web.staticTexts["Collection access denied"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["preview-close"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testPreviewFlagPersistsAfterClosing() {
        let app = XCUIApplication()
        app.launch()
        let menu = app.buttons["collection-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["browser-open"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap(); search.typeText("Rust")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-card-")).firstMatch
        func openPreview() {
            XCTAssertTrue(row.waitForExistence(timeout: 30), app.debugDescription)
            row.press(forDuration: 1)
            app.buttons["プレビュー"].tap()
            let flags = app.buttons["preview-flags"]
            XCTAssertTrue(flags.waitForExistence(timeout: 30), app.debugDescription)
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: flags)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        }
        openPreview()
        let mark = app.buttons["preview-mark"]
        let originalMarkLabel = mark.label
        let toggledMarkLabel = originalMarkLabel == "マークを外す" ? "マークを付ける" : "マークを外す"
        mark.tap()
        let markChanged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", toggledMarkLabel), object: mark)
        XCTAssertEqual(XCTWaiter.wait(for: [markChanged], timeout: 20), .completed)
        let flags = app.buttons["preview-flags"]
        flags.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["preview-flag-4"].tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "フラグ 4"), object: flags)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 20), .completed)
        app.buttons["preview-close"].tap()
        openPreview()
        XCTAssertEqual(flags.label, "フラグ 4", app.debugDescription)
        XCTAssertEqual(mark.label, toggledMarkLabel, app.debugDescription)
        mark.tap()
        let markRestored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", originalMarkLabel), object: mark)
        XCTAssertEqual(XCTWaiter.wait(for: [markRestored], timeout: 20), .completed)
        flags.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["preview-flag-0"].tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "フラグなし"), object: flags)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 20), .completed)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testSwipeCanRevealAndAnswerThenUndo() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()
        let reveal = app.buttons["reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 30))
        let revealReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: reveal)
        XCTAssertEqual(XCTWaiter.wait(for: [revealReady], timeout: 30), .completed)
        let web = app.webViews.firstMatch
        web.swipeLeft()
        let good = app.buttons["answer-2"]
        XCTAssertTrue(good.waitForExistence(timeout: 20), app.debugDescription)
        let answerReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: good)
        XCTAssertEqual(XCTWaiter.wait(for: [answerReady], timeout: 20), .completed)
        web.swipeLeft()
        let answered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: good)
        XCTAssertEqual(XCTWaiter.wait(for: [answered], timeout: 30), .completed, app.debugDescription)
        let undo = app.buttons["取り消す"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: undo)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        undo.tap()
        XCTAssertTrue(reveal.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testZImageOcclusionCanBeCreatedFromPhoto() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        func firstNumber(_ value: String) -> Int {
            value.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init).first ?? -1
        }
        let original = firstNumber(deck.label)
        XCTAssertGreaterThanOrEqual(original, 0)
        let menu = app.buttons["collection-menu"]
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["add-occlusion"].tap()
        let photos = app.buttons["occlusion-select-photo"]
        XCTAssertTrue(photos.waitForExistence(timeout: 20))
        photos.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "キャンセル"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 30), app.debugDescription)
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 30), app.debugDescription)
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 30), app.debugDescription)
        let imageReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            web.images.allElementsBoundByIndex.contains { $0.frame.width > 100 && $0.frame.height > 100 }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [imageReady], timeout: 45), .completed, app.debugDescription)
        guard let image = web.images.allElementsBoundByIndex.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { XCTFail(app.debugDescription); return }
        image.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2)).press(forDuration: 0.1, thenDragTo: image.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.55)))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "iPad-image-occlusion-mask"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["occlusion-save"].tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: web)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 30), .completed, app.debugDescription)
        XCTAssertTrue(deck.waitForExistence(timeout: 30), app.debugDescription)
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in firstNumber(deck.label) == original + 1 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 20), .completed, deck.label)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testZZSharedDeckCanBeDownloadedAndImported() {
        let app = XCUIApplication()
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

    func testZZZProfilesKeepCollectionsAndAccountsSeparate() {
        let app = XCUIApplication()
        app.launch()
        let account = app.buttons["ankiweb-account"]
        XCTAssertTrue(account.waitForExistence(timeout: 30))
        account.tap()
        let username = app.textFields["login-username"]
        XCTAssertTrue(username.waitForExistence(timeout: 20))
        username.tap(); username.typeText("fixture@example.test")
        app.secureTextFields["login-password"].tap()
        app.secureTextFields["login-password"].typeText("fixture-password")
        app.switches["custom-server-toggle"].switches.firstMatch.tap()
        let endpoint = app.textFields["custom-server-endpoint"]
        XCTAssertTrue(endpoint.waitForExistence(timeout: 20))
        endpoint.tap(); endpoint.typeText("http://127.0.0.1:18891/")
        app.buttons["login-submit"].tap()
        let upload = app.buttons["このiPadのデータをAnkiWebにアップロード"]
        let download = app.buttons["AnkiWebのデータをこのiPadにダウンロード"].firstMatch
        let syncChoice = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in upload.exists || download.exists || app.staticTexts["同期しました"].exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [syncChoice], timeout: 60), .completed, app.debugDescription)
        if upload.exists || download.exists {
            XCTAssertTrue(download.exists, "The fixture server must not be overwritten by this isolation test")
            download.tap()
            let replace = app.alerts.buttons["置き換えて同期"]
            XCTAssertTrue(replace.waitForExistence(timeout: 20))
            replace.tap()
        }
        XCTAssertTrue(app.staticTexts["同期しました"].waitForExistence(timeout: 60), app.debugDescription)
        let originalDeck = app.buttons["deck-1"]
        XCTAssertTrue(originalDeck.waitForExistence(timeout: 20), app.debugDescription)
        let originalLabel = originalDeck.label
        func counts() -> [Int] { originalDeck.label.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init) }
        XCTAssertNotEqual(counts(), [0, 0, 0])
        func openProfiles() {
            let menu = app.buttons["collection-menu"]
            XCTAssertTrue(menu.waitForExistence(timeout: 30))
            menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            app.buttons["profiles-open"].tap()
            XCTAssertTrue(app.buttons["profile-default"].waitForExistence(timeout: 20), app.debugDescription)
        }
        openProfiles()
        app.buttons["profile-add"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 20))
        name.tap(); name.typeText("Secondary")
        app.alerts.buttons.matching(identifier: "profile-save").firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let login = app.buttons["login-entry"]
        XCTAssertTrue(login.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(originalDeck.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertEqual(counts(), [0, 0, 0], app.debugDescription)
        XCTAssertFalse(app.staticTexts["fixture@example.test"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(login.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(originalDeck.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertEqual(counts(), [0, 0, 0], app.debugDescription)
        openProfiles()
        app.buttons["profile-default"].tap()
        XCTAssertTrue(originalDeck.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertEqual(originalDeck.label, originalLabel, app.debugDescription)
        XCTAssertTrue(app.staticTexts["fixture@example.test"].exists, app.debugDescription)
        openProfiles()
        let secondary = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Secondary")).firstMatch
        XCTAssertTrue(secondary.waitForExistence(timeout: 20))
        secondary.press(forDuration: 1)
        app.buttons["削除"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 20), app.debugDescription)
        app.alerts.buttons["削除"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: secondary)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 20), .completed, app.debugDescription)
        app.buttons["profiles-close"].tap()
        XCTAssertTrue(originalDeck.waitForExistence(timeout: 20))
        XCTAssertEqual(originalDeck.label, originalLabel, app.debugDescription)
        XCTAssertTrue(app.staticTexts["fixture@example.test"].exists)
        account.tap(); app.buttons["logout"].tap(); app.buttons["閉じる"].firstMatch.tap()
        XCTAssertTrue(login.waitForExistence(timeout: 20))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

}
