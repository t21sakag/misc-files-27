import XCTest

final class StudyFlowTests: StudyFlowTestSupport {
    func testAnkiWebLoginAndTokenSurviveRelaunch() {
        let app = makeApplication()
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
        configureSyncEndpoint(app, server: syncEndpoint())
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

    func testFullSyncConflictShowsLocalCounts() {
        let app = makeApplication()
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
        let app = makeApplication()
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

    func testSyncFinishesInBackground() {
        let app = makeApplication()
        let profile = prepareSyncProfile(app, name: "Background completion check", withFixture: false,
            extraArguments: ["--uitest-sync-timing"])
        loginToSyncFixture(app, username: "fixture@example.test", server: syncEndpoint(delayed: true))
        XCTAssertTrue(app.staticTexts.matching(identifier: "空のコレクションにAnkiWebからダウンロード中…").firstMatch.waitForExistence(timeout: 60), app.debugDescription)
        XCUIDevice.shared.press(.home)
        // The proxy holds the response for twelve seconds. Let it finish while
        // the app is backgrounded, then inspect the foreground result.
        Thread.sleep(forTimeInterval: 20)
        let beforeActivation = Date().timeIntervalSince1970
        app.activate()
        XCTAssertTrue(app.staticTexts["同期しました"].waitForExistence(timeout: 60), app.debugDescription)
        let completedAt = app.staticTexts["sync-completed-at"]
        XCTAssertTrue(completedAt.exists)
        XCTAssertLessThanOrEqual(Double(completedAt.label) ?? .infinity, beforeActivation,
            "Sync must complete before activation, rather than merely resume after it")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        removeSyncProfile(app, id: profile)
    }

    func testSyncExpirationNotifiesAndRetriesFullDownload() {
        let app = makeApplication()
        let profile = prepareSyncProfile(app, name: "Background expiration check", withFixture: false,
            extraArguments: ["--uitest-expire-full-download"])
        loginToSyncFixture(app, username: "fixture@example.test", server: syncEndpoint(delayed: true))
        let interrupted = app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "前回の同期が中断されました")).firstMatch
        XCTAssertTrue(interrupted.waitForExistence(timeout: 60), app.debugDescription)
        app.alerts.buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30))
        app.terminate()
        app.launchArguments = []
        app.launch()
        let sync = app.buttons["sync"]
        XCTAssertTrue(sync.waitForExistence(timeout: 30))
        sync.tap()
        XCTAssertTrue(app.staticTexts["同期しました"].waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        removeSyncProfile(app, id: profile)
    }

    func testSyncInterruptedLaunchWarnsAfterTermination() {
        let app = makeApplication()
        let profile = prepareSyncProfile(app, name: "Interrupted launch check", withFixture: false)
        loginToSyncFixture(app, username: "fixture@example.test", server: syncEndpoint(delayed: true))
        XCTAssertTrue(app.staticTexts.matching(identifier: "空のコレクションにAnkiWebからダウンロード中…").firstMatch.waitForExistence(timeout: 60), app.debugDescription)
        app.terminate()
        app.launchArguments = []
        app.launch()
        let interrupted = app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "前回の同期が中断されました")).firstMatch
        XCTAssertTrue(interrupted.waitForExistence(timeout: 60), app.debugDescription)
        app.alerts.buttons["閉じる"].tap()
        app.buttons["sync"].tap()
        XCTAssertTrue(app.staticTexts["同期しました"].waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        removeSyncProfile(app, id: profile)
    }

    func testZZZProfilesKeepCollectionsAndAccountsSeparate() {
        let app = makeApplication()
        app.launch()
        let account = app.buttons["ankiweb-account"]
        XCTAssertTrue(account.waitForExistence(timeout: 30))
        account.tap()
        let username = app.textFields["login-username"]
        XCTAssertTrue(username.waitForExistence(timeout: 20))
        username.tap(); username.typeText("fixture@example.test")
        app.secureTextFields["login-password"].tap()
        app.secureTextFields["login-password"].typeText("fixture-password")
        configureSyncEndpoint(app, server: syncEndpoint())
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
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(login.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(originalDeck.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertEqual(counts(), [0, 0, 0], app.debugDescription)
        openProfiles()
        app.buttons["profile-default"].tap()
        XCTAssertTrue(originalDeck.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertEqual(originalDeck.label, originalLabel, app.debugDescription)
        XCTAssertTrue(app.staticTexts["fixture@example.test"].exists, app.debugDescription)
        openProfiles()
        let beforeRename = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Secondary")).firstMatch
        XCTAssertTrue(beforeRename.waitForExistence(timeout: 20))
        beforeRename.press(forDuration: 1)
        app.buttons["名前を変更"].tap()
        let rename = app.alerts["名前を変更"].textFields.firstMatch
        XCTAssertTrue(rename.waitForExistence(timeout: 20), app.debugDescription)
        rename.tap()
        rename.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Secondary".count) + "Renamed Secondary")
        app.alerts.buttons["profile-save"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let secondary = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Renamed Secondary")).firstMatch
        XCTAssertTrue(secondary.waitForExistence(timeout: 20))
        XCTAssertTrue(beforeRename.waitForNonExistence(timeout: 20))
        app.buttons["profiles-close"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.staticTexts["fixture@example.test"].waitForExistence(timeout: 30))
        XCTAssertEqual(originalDeck.label, originalLabel)
        openProfiles()
        XCTAssertTrue(secondary.waitForExistence(timeout: 20), "Renamed profile must persist after relaunch")
        secondary.press(forDuration: 1)
        app.buttons["削除"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 20), app.debugDescription)
        app.alerts.buttons["profile-delete-confirm"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: secondary)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 60), .completed, app.debugDescription)
        app.buttons["profiles-close"].tap()
        XCTAssertTrue(originalDeck.waitForExistence(timeout: 20))
        XCTAssertEqual(originalDeck.label, originalLabel, app.debugDescription)
        XCTAssertTrue(app.staticTexts["fixture@example.test"].exists)
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.staticTexts["fixture@example.test"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertEqual(originalDeck.label, originalLabel, app.debugDescription)
        openProfiles()
        XCTAssertFalse(secondary.exists, "Deleted profile must remain absent after relaunch")
        app.buttons["profiles-close"].tap()
        account.tap(); app.buttons["logout"].tap(); app.buttons["閉じる"].firstMatch.tap()
        XCTAssertTrue(login.waitForExistence(timeout: 20))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

}
