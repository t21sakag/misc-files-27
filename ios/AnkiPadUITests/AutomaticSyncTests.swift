import XCTest

final class AutomaticSyncTests: StudyFlowTestSupport {
    override var syncFixturePort: Int { 18901 }

    func testAutomaticSyncRunsAtStartupAndForeground() {
        let app = makeApplication(automaticSync: true)
        let profile = prepareSyncProfile(app, name: "Automatic startup check", withFixture: false,
            extraArguments: ["--uitest-sync-timing"])
        loginToSyncFixture(app, username: "fixture@example.test")
        XCTAssertTrue(app.staticTexts["同期しました"].waitForExistence(timeout: 60), app.debugDescription)
        waitForSyncIdle(app)
        app.terminate()
        let launchedAt = Date().timeIntervalSince1970
        app.launch()
        waitForSyncTimestamp(app, since: launchedAt)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 20)
        let activatedAt = Date().timeIntervalSince1970
        app.activate()
        waitForSyncTimestamp(app, since: activatedAt)
        removeSyncProfile(app, id: profile)
    }

    func testAutomaticSyncPushesChangesInBackground() {
        let app = makeApplication(automaticSync: true)
        let profile = prepareSyncProfile(app, name: "Automatic background check", withFixture: false,
            extraArguments: ["--uitest-sync-timing"])
        loginToSyncFixture(app, username: "fixture@example.test")
        XCTAssertTrue(app.staticTexts["同期しました"].waitForExistence(timeout: 60), app.debugDescription)
        waitForSyncIdle(app)
        addUnsyncedNote(app)
        let startedAt = Date().timeIntervalSince1970
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 20)
        let beforeActivation = Date().timeIntervalSince1970
        app.activate()
        let completedAt = app.staticTexts["background-sync-completed-at"]
        XCTAssertTrue(completedAt.waitForExistence(timeout: 20), app.debugDescription)
        let value = Double(completedAt.label) ?? 0
        XCTAssertGreaterThanOrEqual(value, startedAt)
        XCTAssertLessThanOrEqual(value, beforeActivation)
        XCTAssertFalse(app.staticTexts["sync-local-changes"].exists, app.debugDescription)
        removeSyncProfile(app, id: profile)
    }

    func testAutomaticSyncCanBeDisabledPersistently() {
        let app = makeApplication(automaticSync: true)
        let profile = prepareSyncProfile(app, name: "Automatic disabled check", withFixture: false,
            extraArguments: ["--uitest-sync-timing"])
        loginToSyncFixture(app, username: "fixture@example.test")
        XCTAssertTrue(app.staticTexts["同期しました"].waitForExistence(timeout: 60), app.debugDescription)
        app.buttons["collection-menu"].tap()
        app.buttons["設定"].tap()
        let toggle = app.switches["automatic-sync"].switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.tap()
        app.buttons["settings-save"].tap()
        waitForSyncIdle(app)
        addUnsyncedNote(app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["sync-local-changes"].waitForExistence(timeout: 30))
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 20)
        app.activate()
        XCTAssertTrue(app.staticTexts["sync-local-changes"].exists)
        app.buttons["collection-menu"].tap()
        app.buttons["設定"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["settings-save"].tap()
        removeSyncProfile(app, id: profile)
    }

    func testAutomaticFullUploadRequiresDirectionChoice() {
        let app = makeApplication(automaticSync: true)
        let profile = prepareSyncProfile(app, name: "Automatic upload choice check", extraArguments: ["--uitest-presentation-trace"])
        loginToSyncFixture(app, username: "empty@example.test")
        let confirmation = app.alerts.matching(identifier: "データを置き換えますか？")
        let replace = alertActions(titles: ["置き換えて同期"], in: confirmation)
        guard let initial = waitForTestControl(replace, in: app, keyboard: .keep, timeout: 60, purpose: .observation) else { return }
        XCTAssertFalse(initial.isEnabled, "Empty confirmation cannot upload a local collection")
        tapTestAlertAction(titles: ["キャンセル"], in: confirmation, application: app)
        requireTestCondition("Initial upload confirmation cancels", in: app) { confirmation.count == 0 }
        // Avoid a background transition here: relaunch must initiate this check.
        app.terminate(); app.launchArguments = ["--uitest-presentation-trace"]; app.launch()
        let upload = app.buttons.matching(NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern(["このiPadのデータをAnkiWebにアップロード"])))
        waitForTestControl(upload, in: app, timeout: 60)
        XCTAssertEqual(app.alerts.textFields.count, 0, "Automatic full sync must stop at direction selection")
        XCTAssertFalse(app.staticTexts["同期しました"].exists)
        tapTestControl(upload, in: app)
        guard let next = waitForTestControl(replace, in: app, keyboard: .keep, purpose: .observation) else { return }
        XCTAssertFalse(next.isEnabled, "Choosing upload must still require explicit typed confirmation")
        tapTestAlertAction(titles: ["キャンセル"], in: confirmation, application: app)
        requireTestCondition("Automatic upload confirmation cancels without syncing", in: app) { confirmation.count == 0 }
        XCTAssertFalse(app.staticTexts["同期しました"].exists)
        removeSyncProfile(app, id: profile)
    }

    func testAutomaticFullDownloadRequiresDirectionChoice() {
        let app = makeApplication(automaticSync: true)
        let profile = prepareSyncProfile(app, name: "Automatic full download check", withFixture: false,
                                         extraArguments: ["--uitest-presentation-trace"])
        loginToSyncFixture(app, username: "fixture@example.test", server: syncEndpoint(delayed: true))
        // The same status is also rendered in the bottom busy bar. Observe
        // its deck-list copy uniquely, rather than taking a global first match.
        guard waitForTestControl(app.collectionViews.staticTexts.matching(identifier: "空のコレクションにAnkiWebからダウンロード中…"), in: app,
                                keyboard: .keep, timeout: 60, purpose: .observation) != nil else { return }
        app.terminate(); app.launch()
        let interrupted = app.alerts.matching(identifier: "処理できませんでした")
        waitForTestControl(interrupted.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "前回の同期が中断されました")),
                           in: app, keyboard: .keep, timeout: 30, purpose: .observation)
        tapTestAlertAction(titles: ["閉じる"], in: interrupted, application: app)
        let download = app.buttons.matching(NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern(["AnkiWebのデータをこのiPadにダウンロード"])))
        waitForTestControl(download, in: app, timeout: 60)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern(["このiPadのデータをAnkiWebにアップロード"]))).count, 0)
        XCTAssertFalse(app.staticTexts["同期しました"].exists, "Automatic recovery must not replace the collection before confirmation")
        tapTestControl(download, in: app)
        tapTestAlertAction(titles: ["置き換えて同期"], in: app.alerts.matching(identifier: "データを置き換えますか？"), application: app)
        waitForTestControl(app.staticTexts.matching(identifier: "同期しました"), in: app,
                           keyboard: .keep, timeout: 60, purpose: .observation)
        removeSyncProfile(app, id: profile)
    }

}
