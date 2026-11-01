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
        let profile = prepareSyncProfile(app, name: "Conflict safety check", extraArguments: ["--uitest-presentation-trace"])
        loginToSyncFixture(app, username: "fixture@example.test")
        let download = app.buttons.matching(NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern(["AnkiWebのデータをこのiPadにダウンロード"])))
        guard waitForTestControl(download, in: app, timeout: 60) != nil else { return }
        waitForTestControl(app.buttons.matching(NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern(["このiPadのデータをAnkiWebにアップロード"]))), in: app)
        waitForTestControl(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "このiPad: デッキ 1個・カード 1枚")), in: app, purpose: .observation)
        tapTestControl(download, in: app)
        let confirmation = app.alerts.matching(identifier: "データを置き換えますか？")
        tapTestAlertAction(titles: ["置き換えて同期"], in: confirmation, application: app)
        waitForTestControl(app.staticTexts.matching(identifier: "同期しました"), in: app, timeout: 60, purpose: .observation)
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
        app.launchArguments += ["--uitest-presentation-trace"]
        app.launch()
        loginToSyncFixture(app, username: "fixture@example.test")
        let download = app.buttons.matching(NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern(["AnkiWebのデータをこのiPadにダウンロード"])))
        let upload = app.buttons.matching(NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern(["このiPadのデータをAnkiWebにアップロード"])))
        requireTestCondition("Login reaches a direction choice or completed sync", in: app, timeout: 60) {
            upload.count > 0 || download.count > 0 || app.staticTexts["同期しました"].exists
        }
        if upload.count > 0 || download.count > 0 {
            XCTAssertEqual(download.count, 1, "The fixture server must not be overwritten by this isolation test")
            tapTestControl(download, in: app)
            tapTestAlertAction(titles: ["置き換えて同期"], in: app.alerts.matching(identifier: "データを置き換えますか？"), application: app)
        }
        waitForTestControl(app.staticTexts.matching(identifier: "同期しました"), in: app, timeout: 60, purpose: .observation)
        let decks = app.buttons.matching(identifier: "deck-1")
        guard let originalDeck = waitForTestControl(decks, in: app, purpose: .observation) else { return }
        let originalLabel = originalDeck.label
        func counts() -> [Int] {
            guard let deck = waitForTestControl(decks, in: app, purpose: .observation) else { return [] }
            return deck.label.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
        }
        XCTAssertNotEqual(counts(), [0, 0, 0])
        func openProfiles() {
            tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
            tapTestMenuAction(titles: ["プロファイル"], in: app)
            waitForTestControl(app.buttons.matching(identifier: "profile-default"), in: app)
        }
        func closeProfiles() {
            tapTestControl(app.buttons.matching(identifier: "profiles-close"), in: app)
            requireTestCondition("Profile sheet closes", in: app) { !app.navigationBars["プロファイル"].exists }
        }
        func relaunch() { app.terminate(); app.launchArguments = ["--uitest-presentation-trace"]; app.launch() }
        openProfiles()
        tapTestControl(app.buttons.matching(identifier: "profile-add"), in: app)
        let add = app.alerts.matching(identifier: "プロファイルを追加")
        typeInEmptyTestField(add.textFields, text: "Secondary", in: app)
        tapTestAlertAction("profile-save", in: add, application: app)
        waitForTestControl(app.buttons.matching(identifier: "login-entry"), in: app)
        XCTAssertEqual(counts(), [0, 0, 0])
        XCTAssertFalse(app.staticTexts["fixture@example.test"].exists)
        relaunch()
        waitForTestControl(app.buttons.matching(identifier: "login-entry"), in: app)
        XCTAssertEqual(counts(), [0, 0, 0])
        openProfiles()
        tapTestControl(app.buttons.matching(identifier: "profile-default"), in: app)
        waitForTestControl(decks, in: app)
        XCTAssertEqual(originalDeck.label, originalLabel)
        waitForTestControl(app.staticTexts.matching(identifier: "fixture@example.test"), in: app, purpose: .observation)
        openProfiles()
        let beforeRename = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Secondary"))
        guard let row = waitForTestControl(beforeRename, in: app) else { return }
        let secondaryID = row.identifier
        XCTAssertTrue(secondaryID.hasPrefix("profile-"))
        row.press(forDuration: 1)
        tapTestMenuAction(titles: ["名前を変更"], in: app)
        let rename = app.alerts.matching(identifier: "名前を変更")
        replaceTestField(rename.textFields, expected: "Secondary", with: "Renamed Secondary", in: app)
        tapTestAlertAction("profile-save", in: rename, application: app)
        let secondary = app.buttons.matching(identifier: secondaryID)
        guard let renamed = waitForTestControl(secondary, in: app) else { return }
        XCTAssertTrue(renamed.label.hasPrefix("Renamed Secondary"))
        requireTestCondition("Old profile name is removed", in: app) { beforeRename.count == 0 }
        closeProfiles()
        relaunch()
        waitForTestControl(app.staticTexts.matching(identifier: "fixture@example.test"), in: app, purpose: .observation)
        waitForTestControl(decks, in: app, purpose: .observation)
        XCTAssertEqual(originalDeck.label, originalLabel)
        openProfiles()
        guard let persisted = waitForTestControl(secondary, in: app) else { return }
        XCTAssertTrue(persisted.label.hasPrefix("Renamed Secondary"), "Renamed profile must persist after relaunch")
        persisted.press(forDuration: 1)
        tapTestMenuAction(titles: ["削除"], in: app)
        tapTestAlertAction("profile-delete-confirm", in: app.alerts.matching(identifier: "プロファイルを削除しますか？"), application: app)
        requireTestCondition("Inactive profile is removed", in: app, timeout: 60) { secondary.count == 0 }
        closeProfiles()
        XCTAssertEqual(originalDeck.label, originalLabel)
        waitForTestControl(app.staticTexts.matching(identifier: "fixture@example.test"), in: app, purpose: .observation)
        relaunch()
        waitForTestControl(app.staticTexts.matching(identifier: "fixture@example.test"), in: app, purpose: .observation)
        waitForTestControl(decks, in: app, purpose: .observation)
        XCTAssertEqual(originalDeck.label, originalLabel)
        openProfiles()
        XCTAssertEqual(secondary.count, 0, "Deleted profile must remain absent after relaunch")
        closeProfiles()
        tapTestControl(app.buttons.matching(identifier: "ankiweb-account"), in: app)
        tapTestControl(app.buttons.matching(identifier: "logout"), in: app)
        tapTestControl(app.navigationBars["AnkiWeb"].buttons.matching(identifier: "閉じる"), in: app)
        waitForTestControl(app.buttons.matching(identifier: "login-entry"), in: app)
        XCTAssertFalse(app.alerts.element.exists)
    }

}
