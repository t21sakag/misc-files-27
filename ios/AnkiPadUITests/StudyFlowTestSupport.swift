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

    enum TestKeyboardPolicy { case keep, dismiss }
    enum TestControlPurpose { case action, observation }

    private func controlFailure(_ query: XCUIElementQuery, in app: XCUIApplication, reason: String) {
        let matches = query.allElementsBoundByIndex.prefix(12).map {
            "id=\($0.identifier) label=\($0.label) frame=\($0.frame) enabled=\($0.isEnabled) hittable=\($0.isHittable)"
        }.joined(separator: "\n")
        let evidence = reason + "\n" + query.debugDescription + "\n" + matches + "\n" + app.debugDescription
        XCTContext.runActivity(named: "Control prerequisite failed") { activity in
            let hierarchy = XCTAttachment(string: evidence); hierarchy.name = "Hierarchy and target frames"; hierarchy.lifetime = .keepAlways
            let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways
            activity.add(hierarchy); activity.add(screenshot)
        }
        XCTFail(evidence)
    }

    @discardableResult
    func dismissTestKeyboard(in app: XCUIApplication) -> Bool {
        func visible() -> Bool {
            // The OS may retain an offscreen, zero-height Keyboard node.
            // isHittable returns false for both missing and offscreen elements;
            // never read frame after a separate existence check.
            app.keyboards.allElementsBoundByIndex.contains { $0.isHittable }
        }
        guard visible() else { return true }
        let hide = app.buttons.matching(NSPredicate(format: "label IN %@", ["Hide keyboard", "キーボードを隠す"]))
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !visible() || hide.allElementsBoundByIndex.filter { $0.isHittable }.count == 1
        }, object: nil)
        // AX evaluation can itself outlast the observer deadline. A timeout
        // is not proof that the keyboard/control is still in that old state.
        // Recheck the same required postcondition before failing or acting.
        _ = XCTWaiter.wait(for: [settled], timeout: 10)
        // A sheet dismissal may have already closed its keyboard while the
        // button query was resolving. That is the required end state.
        if !visible() { return true }
        let buttons = hide.allElementsBoundByIndex.filter { $0.isHittable }
        guard buttons.count == 1 else {
            controlFailure(hide, in: app, reason: "Cannot uniquely dismiss the keyboard before a control action")
            return false
        }
        buttons[0].tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !visible() }, object: nil)
        let closedResult = XCTWaiter.wait(for: [closed], timeout: 10)
        guard closedResult == .completed || !visible() else {
            controlFailure(hide, in: app, reason: "Keyboard did not close")
            return false
        }
        return true
    }

    /// New control actions resolve a typed, unique query, handle the keyboard,
    /// reveal lazy rows when requested, and wait for actual hit testing. Failure
    /// records the hierarchy, screen and target coordinates before any retry.
    /// Only optional transient prompts may supply an explicit alreadySatisfied
    /// postcondition. Required controls never skip their readiness checks.
    @discardableResult
    func tapTestControl(_ query: XCUIElementQuery, in app: XCUIApplication, form: XCUIElement? = nil,
                        keyboard: TestKeyboardPolicy = .dismiss, alreadySatisfied: (() -> Bool)? = nil) -> XCUIElement? {
        guard let element = waitForTestControl(query, in: app, form: form, keyboard: keyboard, alreadySatisfied: alreadySatisfied) else { return nil }
        XCTContext.runActivity(named: "Tap native control: " + element.identifier + " " + String(describing: element.frame)) { _ in
            element.tap()
        }
        return element
    }

    /// Native alerts can export a Button containing a second Button with the
    /// same identifier/frame. In the observed action row, only the outer action
    /// is a direct child of an Other container; containing() includes self and
    /// does not disambiguate these wrappers. Preserve strict unique readiness.
    @discardableResult
    func tapTestAlertAction(_ identifier: String, in alert: XCUIElementQuery, application: XCUIApplication) -> XCUIElement? {
        let actions = alert.descendants(matching: .other).children(matching: .button).matching(identifier: identifier)
        return tapTestControl(actions, in: application, keyboard: .keep)
    }

    @discardableResult
    func tapTestAlertAction(titles: [String], in alert: XCUIElementQuery, application: XCUIApplication) -> XCUIElement? {
        let actions = alert.descendants(matching: .other).children(matching: .button)
            .matching(NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern(titles)))
        return tapTestControl(actions, in: application, keyboard: .keep)
    }

    /// Native submenu cells can omit the source accessibility identifier.
    /// Match the full observed title within actual menu cell buttons, retaining
    /// the shared one-match/actionable checks instead of choosing the first.
    func testMenuActions(titles: [String], in app: XCUIApplication) -> XCUIElementQuery {
        app.collectionViews.children(matching: .cell).children(matching: .button)
            .matching(NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern(titles)))
    }

    @discardableResult
    func tapTestMenuAction(titles: [String], in app: XCUIApplication) -> XCUIElement? {
        tapTestControl(testMenuActions(titles: titles, in: app), in: app, keyboard: .keep)
    }

    /// SwiftUI can export a labelled full-row Switch wrapping the native
    /// thumb. Activate its unique direct Switch child, not the row's centre.
    @discardableResult
    func setTestSwitch(_ query: XCUIElementQuery, enabled: Bool, in app: XCUIApplication) -> Bool {
        guard waitForTestControl(query, in: app, purpose: .observation) != nil else { return false }
        let children = query.children(matching: .switch)
        let native = children.count > 0 ? children : query
        guard let control = waitForTestControl(native, in: app) else { return false }
        let desired = enabled ? "1" : "0"
        guard ["0", "1"].contains(control.value as? String ?? "") else {
            controlFailure(native, in: app, reason: "Switch does not expose an on/off value"); return false
        }
        if control.value as? String != desired {
            guard tapTestControl(native, in: app) != nil else { return false }
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in control.value as? String == desired }, object: nil)
        guard XCTWaiter.wait(for: [changed], timeout: 10) == .completed else {
            controlFailure(native, in: app, reason: "Native switch did not reach the requested state"); return false
        }
        return true
    }

    /// Native empty fields may export their placeholder as value. Prove the
    /// initial content by inserting a sentinel and checking the entire result;
    /// accepting value == placeholder alone would also accept literal content.
    @discardableResult
    func typeInEmptyTestField(_ query: XCUIElementQuery, text: String, in app: XCUIApplication,
                              form: XCUIElement? = nil) -> XCUIElement? {
        guard !text.isEmpty, let field = tapTestControl(query, in: app, form: form) else { return nil }
        let value = field.value as? String
        guard value == "" || (field.placeholderValue != nil && value == field.placeholderValue) else {
            controlFailure(query, in: app, reason: "Expected an empty field before inserting test text"); return nil
        }
        field.typeText(text)
        guard field.value as? String == text else {
            controlFailure(query, in: app, reason: "Field did not contain exactly the inserted test text"); return nil
        }
        return field
    }

    /// Readiness is also required before reading a value: remote widgets can
    /// expose both placeholder/redaction and live nodes with the same ID.
    @discardableResult
    func waitForTestControl(_ query: XCUIElementQuery, in app: XCUIApplication, form: XCUIElement? = nil,
                            keyboard: TestKeyboardPolicy = .dismiss, alreadySatisfied: (() -> Bool)? = nil,
                            timeout: TimeInterval = 20, purpose: TestControlPurpose = .action) -> XCUIElement? {
        if alreadySatisfied?() == true { return nil }
        if case .dismiss = keyboard, !dismissTestKeyboard(in: app) { return nil }
        if let form { revealFormControl(query.firstMatch, in: form, topInset: 40, bottomInset: 20, maximumAttempts: 12) }
        let exists = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in alreadySatisfied?() == true || query.count == 1 }, object: nil)
        guard XCTWaiter.wait(for: [exists], timeout: timeout) == .completed else {
            controlFailure(query, in: app, reason: "Control did not settle to one match; scope its foreground container and semantic state"); return nil
        }
        if alreadySatisfied?() == true { return nil }
        guard query.count == 1 else {
            controlFailure(query, in: app, reason: "Control query is ambiguous; scope its container/type explicitly"); return nil
        }
        let element = query.element(boundBy: 0)
        let predicate = NSPredicate { _, _ in
            if alreadySatisfied?() == true { return true }
            guard query.count == 1 && element.exists else { return false }
            switch purpose {
            case .action: return element.isEnabled && element.isHittable
            case .observation:
                let visible = element.frame.intersection(app.frame)
                return !visible.isNull && visible.width > 0 && visible.height > 0
            }
        }
        let ready = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        guard XCTWaiter.wait(for: [ready], timeout: timeout) == .completed else {
            controlFailure(query, in: app, reason: "Control did not become actionable"); return nil
        }
        if alreadySatisfied?() == true { return nil }
        return element
    }

    func openTestShareService(in host: XCUIApplication, useAppsList: Bool = false) {
        let composer = host.textFields.matching(identifier: "share-subject")
        let apps = host.otherElements.matching(identifier: "AppsView").tables.matching(identifier: "tableView")
        let service = host.cells.matching(NSPredicate(format: "identifier == %@ AND label == %@", "shareCell", "AnkiPad"))
        let more = host.cells.matching(NSPredicate(format: "identifier == %@ AND label IN %@", "shareCell", ["More", "その他"]))
        let knownScreen = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            composer.firstMatch.exists || apps.firstMatch.exists
                || (!useAppsList && service.firstMatch.exists && service.firstMatch.isHittable)
                || (more.firstMatch.exists && more.firstMatch.isHittable)
        }, object: nil)
        guard XCTWaiter.wait(for: [knownScreen], timeout: 20) == .completed else {
            controlFailure(host.cells, in: host, reason: "No known foreground share presentation"); return
        }
        if !composer.firstMatch.exists {
            if !useAppsList && !apps.firstMatch.exists && service.firstMatch.exists && service.firstMatch.isHittable {
                guard tapTestControl(service, in: host) != nil else { return }
            } else {
                if !apps.firstMatch.exists {
                    guard tapTestControl(more, in: host) != nil else { return }
                }
                guard apps.firstMatch.waitForExistence(timeout: 20), apps.count == 1 else {
                    controlFailure(apps, in: host, reason: "More did not present one foreground Apps table"); return
                }
                // Apps rows have no label themselves. The label is on their
                // activityTitleLabel child; the old icon remains behind this
                // sheet and must never be reused as the selection target.
                let row = apps.cells.containing(.staticText, identifier: "AnkiPad")
                guard tapTestControl(row, in: host, form: apps.element(boundBy: 0)) != nil else { return }
            }
        }
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true AND hittable == true"), object: composer.firstMatch)
        guard XCTWaiter.wait(for: [loaded], timeout: 20) == .completed else {
            controlFailure(composer, in: host, reason: "Share service did not reach its editable composer"); return
        }
    }

    func completeTestShare(in host: XCUIApplication, subject: String) {
        let query = host.textFields.matching(identifier: "share-subject")
        guard let field = tapTestControl(query, in: host, keyboard: .keep) else { return }
        let old = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)+subject)
        tapTestControl(host.buttons.matching(identifier: "share-submit"), in: host)
        tapTestControl(host.buttons.matching(identifier: "share-complete"), in: host)
    }

    /// Photos exposes its grid before the delayed first-launch sheet appears.
    /// Keep this environment prerequisite ahead of the actual share journey.
    func prepareTestPhotoLibrary(_ photos: XCUIApplication) {
        XCTContext.runActivity(named: "Prerequisite: photo host and imported fixture") { _ in
            photos.launch()
            let welcome = photos.buttons.matching(NSPredicate(format: "label IN %@", ["Continue", "続ける"]))
            if welcome.firstMatch.waitForExistence(timeout: 15) {
                tapTestControl(welcome, in: photos)
                XCTAssertTrue(welcome.firstMatch.waitForNonExistence(timeout: 15), photos.debugDescription)
            }
            let images = photos.images.matching(identifier: "PXGGridLayout-Info")
            XCTAssertTrue(images.firstMatch.waitForExistence(timeout: 25), photos.debugDescription)
            guard images.count > 0 else { return }
            // All Photos is chronological. Current-year labels omit the year.
            let image = images.element(boundBy: images.count-1)
            waitUntilHittable(image)
            XCTContext.runActivity(named: "Select fixture image: " + String(describing: image.frame)) { _ in
                image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
        }
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
