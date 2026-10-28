import XCTest

final class SyncSettingsFlowTests: StudyFlowTestSupport {
    private func openSettings(_ app: XCUIApplication) {
        let menu = app.buttons["collection-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.tap(); app.buttons["設定"].tap()
        XCTAssertTrue(app.collectionViews["settings-form"].waitForExistence(timeout: 20))
    }
    private func setSwitch(_ app: XCUIApplication, _ id: String, enabled: Bool) {
        let outer = app.switches[id]
        XCTAssertTrue(outer.waitForExistence(timeout: 20))
        let item = outer.switches.firstMatch.exists ? outer.switches.firstMatch : outer
        waitUntilHittable(item)
        let desired = enabled ? "1" : "0"
        if item.value as? String != desired {
            item.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", desired), object: item)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed, app.debugDescription)
    }
    func testNetworkSyncSettingsSurviveRelaunchAndCancelDoesNotSave() {
        let app = makeApplication()
        app.launch()
        openSettings(app)
        setSwitch(app, "sync-allow-metered", enabled: true)
        setSwitch(app, "sync-status-badge", enabled: false)
        let media = app.buttons["sync-media-fetch"]
        XCTAssertTrue(media.waitForExistence(timeout: 20)); media.tap()
        app.buttons["取得しない"].firstMatch.tap()
        let timeout = app.steppers["sync-timeout"]
        XCTAssertTrue(timeout.waitForExistence(timeout: 20))
        timeout.buttons.matching(NSPredicate(format: "label IN %@", ["Increment", "増加"])).firstMatch.tap()
        app.buttons["settings-save"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        openSettings(app)
        XCTAssertEqual(app.switches["sync-allow-metered"].value as? String, "1")
        XCTAssertEqual(app.switches["sync-status-badge"].value as? String, "0")
        XCTAssertTrue(media.label.contains("取得しない"), app.debugDescription)
        XCTAssertTrue(timeout.label.contains("70"), app.debugDescription)
        setSwitch(app, "sync-allow-metered", enabled: false)
        app.navigationBars["設定"].buttons["キャンセル"].tap()
        openSettings(app)
        XCTAssertEqual(app.switches["sync-allow-metered"].value as? String, "1", "Cancelled settings must not overwrite saved policy")
    }
    func testRequestedOneWaySyncPresentsSafeDirectionChoice() {
        let app = makeApplication()
        _ = prepareSyncProfile(app, name: "One way settings", withFixture: false)
        loginToSyncFixture(app, username: "fixture@example.test")
        XCTAssertTrue(app.staticTexts["同期しました"].waitForExistence(timeout: 60), app.debugDescription)
        openSettings(app)
        let oneWay = app.buttons["sync-force-one-way"]
        for _ in 0..<5 {
            if oneWay.exists && oneWay.isHittable { break }
            app.collectionViews["settings-form"].swipeUp()
        }
        waitUntilHittable(oneWay); oneWay.tap()
        let prompt = app.alerts["次回の同期を一方向にしますか？"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 20))
        prompt.buttons["キャンセル"].tap()
        XCTAssertTrue(prompt.waitForNonExistence(timeout: 20))
        oneWay.tap()
        app.buttons["sync-force-one-way-confirm"].firstMatch.tap()
        app.buttons["settings-save"].tap()
        waitForSyncIdle(app)
        app.buttons["sync"].tap()
        XCTAssertTrue(app.buttons["AnkiWebのデータをこのiPadにダウンロード"].waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertTrue(app.buttons["このiPadのデータをAnkiWebにアップロード"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "このiPad: デッキ")).firstMatch.exists)
        XCTAssertFalse(app.alerts.buttons["置き換えて同期"].exists, "Requesting one-way sync must not silently choose an upload")
    }
}
