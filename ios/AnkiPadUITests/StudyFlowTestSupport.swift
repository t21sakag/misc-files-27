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

    func reminderFailureContext(_ app: XCUIApplication) -> String {
        let state = app.staticTexts["reminder-native-schedule"]
        let phase = app.staticTexts["reminder-save-state"]
        return "OS schedule: " + (state.exists ? String(describing: state.value) : "missing")
            + "\nSave phase: " + (phase.exists ? String(describing: phase.value) : "missing")
            + "\n" + app.debugDescription
    }

    func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 30) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed)
    }

    func tapScreenFrame(_ element: XCUIElement, in app: XCUIApplication) {
        waitUntilHittable(element)
        let frame = element.frame, origin = app.frame.origin
        // WebKit can add its content offset again to element-relative taps.
        // Anchor at the native app instead of using the Web accessibility node.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: frame.midX - origin.x, dy: frame.midY - origin.y)).tap()
    }

    func revealSettingsControl(_ item: XCUIElement, in app: XCUIApplication) {
        let form = app.collectionViews["settings-form"]
        revealFormControl(item, in: form)
    }

    func revealFormControl(_ item: XCUIElement, in form: XCUIElement,
                           topInset: CGFloat = 150, bottomInset: CGFloat = 80, maximumAttempts: Int = 40, searchUpward: Bool = true) {
        XCTAssertTrue(form.waitForExistence(timeout: 20))
        for attempt in 0..<maximumAttempts {
            let viewport = form.frame
            let lower = viewport.maxY - bottomInset, upper = viewport.minY + topInset
            let frame = item.exists ? item.frame : .zero
            let located = frame.width > 0 && frame.height > 0
            if located && frame.minY >= upper && frame.maxY <= lower && item.isHittable {
                print("UI reveal \(item.identifier): \(attempt) drags")
                return
            }
            let upward = located ? frame.maxY > lower : searchUpward
            // Large steps retain at least 80pt of overlap in the usable area;
            // when the row is known, stop near it rather than overshooting.
            let far = min(0.45, max(0.1, (lower - upper - 80) / viewport.height))
            let delta = upward ? frame.maxY - lower : upper - frame.minY
            let distance = located ? min(far, max(0.1, delta / viewport.height + 0.03)) : far
            let start: CGFloat = upward ? 0.75 : 0.25
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: start))
                .press(forDuration: 0.1, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: start + (upward ? -distance : distance))), withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTFail("Form control did not become fully visible: " + form.debugDescription)
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
        tapScreenFrame(app.buttons["設定"], in: app)
        let toggle = app.switches["allow-collection-card-api"]
        revealSettingsControl(toggle, in: app)
        let control = toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle
        if (control.value as? String == "1") != enabled {
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        }
        XCTAssertEqual(control.value as? String, enabled ? "1" : "0")
        app.buttons["settings-save"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForNonExistence(timeout: 30))
    }

}
