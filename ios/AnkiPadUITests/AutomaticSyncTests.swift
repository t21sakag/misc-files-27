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
        let profile = prepareSyncProfile(app, name: "Automatic upload choice check")
        loginToSyncFixture(app, username: "empty@example.test")
        let replace = app.alerts.buttons["置き換えて同期"]
        XCTAssertTrue(replace.waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertFalse(replace.isEnabled)
        app.alerts.buttons["キャンセル"].tap()
        // Avoid a background transition here: relaunch must initiate this check.
        app.terminate(); app.launchArguments = []; app.launch()
        let upload = app.buttons["このiPadのデータをAnkiWebにアップロード"]
        XCTAssertTrue(upload.waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertFalse(app.alerts.textFields.firstMatch.exists)
        XCTAssertFalse(app.staticTexts["同期しました"].exists)
        upload.tap()
        XCTAssertTrue(replace.waitForExistence(timeout: 20))
        XCTAssertFalse(replace.isEnabled)
        app.alerts.buttons["キャンセル"].tap()
        removeSyncProfile(app, id: profile)
    }

    func testAutomaticFullDownloadRequiresDirectionChoice() {
        let app = makeApplication(automaticSync: true)
        let profile = prepareSyncProfile(app, name: "Automatic full download check", withFixture: false)
        loginToSyncFixture(app, username: "fixture@example.test", server: syncEndpoint(delayed: true))
        XCTAssertTrue(app.staticTexts.matching(identifier: "空のコレクションにAnkiWebからダウンロード中…").firstMatch.waitForExistence(timeout: 60))
        app.terminate(); app.launch()
        let interrupted = app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "前回の同期が中断されました")).firstMatch
        XCTAssertTrue(interrupted.waitForExistence(timeout: 30), app.debugDescription)
        app.alerts.buttons["閉じる"].tap()
        let download = app.buttons["AnkiWebのデータをこのiPadにダウンロード"]
        XCTAssertTrue(download.waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertFalse(app.buttons["このiPadのデータをAnkiWebにアップロード"].exists)
        XCTAssertFalse(app.staticTexts["同期しました"].exists)
        download.tap()
        app.alerts.buttons["置き換えて同期"].tap()
        XCTAssertTrue(app.staticTexts["同期しました"].waitForExistence(timeout: 60), app.debugDescription)
        removeSyncProfile(app, id: profile)
    }

}
