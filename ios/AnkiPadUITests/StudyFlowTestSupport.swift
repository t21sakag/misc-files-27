import XCTest

class StudyFlowTestSupport: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    private var launchedApplications: [XCUIApplication] = []

    override func tearDownWithError() throws {
        // Release WebKit/audio/keyboard activity before the next case starts.
        for app in launchedApplications where app.state != .notRunning { app.terminate() }
        launchedApplications.removeAll()
        try super.tearDownWithError()
    }

    func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 30) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed)
    }

    func revealSettingsControl(_ item: XCUIElement, in app: XCUIApplication) {
        let form = app.collectionViews["settings-form"]
        XCTAssertTrue(form.waitForExistence(timeout: 20))
        for _ in 0..<24 {
            let lower = form.frame.maxY - 80, upper = form.frame.minY + 150
            if item.exists && item.isHittable && item.frame.minY >= upper && item.frame.maxY <= lower { return }
            let upward = !item.exists || item.frame.maxY > lower
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.65 : 0.35))
                .press(forDuration: 0.1, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.45 : 0.55)), withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTFail("Settings control did not become fully visible: " + app.debugDescription)
    }

    var syncFixturePort: Int { 18891 }
    func syncEndpoint(delayed: Bool = false) -> String {
        "http://127.0.0.1:\(syncFixturePort + (delayed ? 2 : 0))/"
    }

    func makeApplication(automaticSync: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        launchedApplications.append(app)
        app.launchEnvironment["ANKIPAD_UI_TEST_NAMESPACE"] = UUID().uuidString
        app.launchArguments = ["--uitest-fixture"]
        if !automaticSync { app.launchEnvironment["ANKIPAD_UI_TEST_DISABLE_AUTOSYNC"] = "1" }
        return app
    }

    func prepareSyncProfile(_ app: XCUIApplication, name: String, withFixture: Bool = true, extraArguments: [String] = []) -> String {
        // Each case already owns a unique root and Keychain namespace. Use its
        // real default profile instead of creating/deleting another via UI in
        // every sync case. Profile CRUD/isolation has its own dedicated case.
        XCTAssertNotNil(UUID(uuidString: app.launchEnvironment["ANKIPAD_UI_TEST_NAMESPACE"] ?? ""))
        app.launchArguments = (withFixture ? ["--uitest-fixture"] : []) + extraArguments
        app.launch()
        XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.buttons["login-entry"].waitForExistence(timeout: 30), app.debugDescription)
        return "profile-default"
    }

    func removeSyncProfile(_ app: XCUIApplication, id: String) {
        // Do not delete a default/legacy profile. The entire case root is
        // isolated and no later case can read it, including its Keychain items.
        XCTAssertEqual(id, "profile-default")
        XCTAssertNotNil(UUID(uuidString: app.launchEnvironment["ANKIPAD_UI_TEST_NAMESPACE"] ?? ""))
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
        app.terminate()
    }

    func configureSyncEndpoint(_ app: XCUIApplication, server: String) {
        let control = app.switches["custom-server-toggle"].switches.firstMatch
        for _ in 0..<4 {
            if control.exists && control.isHittable { break }
            app.collectionViews["account-form"].swipeUp()
        }
        XCTAssertTrue(control.waitForExistence(timeout: 15), app.debugDescription)
        for _ in 0..<2 {
            if control.value as? String == "1" { break }
            control.tap()
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: control)
            if XCTWaiter.wait(for: [enabled], timeout: 3) == .completed { break }
            app.collectionViews["account-form"].swipeUp()
        }
        XCTAssertEqual(control.value as? String, "1", app.debugDescription)
        let endpoint = app.textFields["custom-server-endpoint"]
        XCTAssertTrue(endpoint.waitForExistence(timeout: 20), app.debugDescription)
        endpoint.tap(); endpoint.typeText(server)
    }

    func loginToSyncFixture(_ app: XCUIApplication, username value: String, server: String? = nil) {
        let account = app.buttons["ankiweb-account"]
        XCTAssertTrue(account.waitForExistence(timeout: 30))
        account.tap()
        let username = app.textFields["login-username"]
        XCTAssertTrue(username.waitForExistence(timeout: 20))
        username.tap(); username.typeText(value)
        app.secureTextFields["login-password"].tap()
        app.secureTextFields["login-password"].typeText("fixture-password")
        configureSyncEndpoint(app, server: server ?? syncEndpoint())
        app.buttons["login-submit"].tap()
    }

    func waitForSyncIdle(_ app: XCUIApplication) {
        let sync = app.buttons["sync"]
        let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: sync)
        XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 30), .completed, app.debugDescription)
    }

    func addUnsyncedNote(_ app: XCUIApplication, frontText: String = "Automatic sync verification") {
        app.buttons["add-note"].tap()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20), app.debugDescription)
        front.tap(); front.typeText(frontText)
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["note-close"].tap()
        XCTAssertTrue(app.staticTexts["sync-local-changes"].waitForExistence(timeout: 20), app.debugDescription)
    }

    func waitForSyncTimestamp(_ app: XCUIApplication, since: TimeInterval) {
        let timestamp = app.staticTexts["sync-completed-at"]
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            timestamp.exists && (Double(timestamp.label) ?? 0) >= since
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 60), .completed, app.debugDescription)
    }

    func openMaintenance(_ app: XCUIApplication) {
        let menu = app.buttons["collection-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["バックアップとチェック"].tap()
        XCTAssertTrue(app.buttons["backup-create"].waitForExistence(timeout: 20))
    }

    func createStoredBackup(_ app: XCUIApplication) -> String {
        app.buttons["backup-create"].tap()
        XCTAssertTrue(app.staticTexts["バックアップを作成しました"].waitForExistence(timeout: 30), app.debugDescription)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "backup-restore-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), app.debugDescription)
        return String(row.identifier.dropFirst("backup-restore-".count))
    }

    func assertBrowserContains(_ app: XCUIApplication, text: String, exists: Bool) {
        app.buttons["collection-menu"].tap()
        app.buttons["browser-open"].tap()
        let search = app.searchFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", "検索（")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        let clear = search.buttons["Clear text"]
        if clear.exists { clear.tap(); search.tap() }
        search.typeText(text)
        let results = app.staticTexts["browser-results"]
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: results)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 20), .completed, app.debugDescription)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-card-")).firstMatch
        if exists { XCTAssertTrue(row.waitForExistence(timeout: 20), app.debugDescription) }
        else {
            let absent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: row)
            XCTAssertEqual(XCTWaiter.wait(for: [absent], timeout: 20), .completed, app.debugDescription)
        }
        app.buttons["閉じる"].firstMatch.tap()
    }

    func setCollectionPermission(_ app: XCUIApplication, enabled: Bool) {
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

}
