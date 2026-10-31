import XCTest

final class BrowserToolsFlowTests: StudyFlowTestSupport {
    private func capture(_ stage: String, in app: XCUIApplication) {
        XCTContext.runActivity(named: stage) { activity in
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = stage + " hierarchy"; hierarchy.lifetime = .keepAlways
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = stage; screenshot.lifetime = .keepAlways
            activity.add(hierarchy); activity.add(screenshot)
        }
    }
    private func addNote(_ text: String, in app: XCUIApplication) {
        guard tapTestControl(app.buttons.matching(identifier: "add-note"), in: app) != nil else { return }
        guard let field = tapTestControl(app.textViews.matching(identifier: "note-field-0"), in: app,
                                         form: app.collectionViews["note-form"]) else { return }
        field.typeText(text)
        guard tapTestControl(app.buttons.matching(identifier: "note-save"), in: app) != nil else { return }
        guard waitForTestControl(app.staticTexts.matching(identifier: "note-added"), in: app, purpose: .observation) != nil else { return }
        tapTestControl(app.buttons.matching(identifier: "note-close"), in: app)
        XCTAssertTrue(app.buttons["add-note"].waitForExistence(timeout: 20))
    }
    private func browser(_ search: String, count: Int, notesMode: Bool = false, in app: XCUIApplication) {
        var url = URLComponents(string: "studyclient://x-callback-url/browser")!
        url.queryItems = [URLQueryItem(name: "search", value: search)]
        app.open(url.url!)
        let results = app.staticTexts.matching(identifier: "browser-results")
        guard let state = waitForTestControl(results, in: app, purpose: .observation) else { return }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            state.value as? String == search && state.label.contains("\(count)" + (notesMode ? "ノート" : "枚"))
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, app.debugDescription)
    }
    private func closeBrowser(_ app: XCUIApplication) {
        tapTestControl(app.navigationBars.buttons.matching(NSPredicate(format: "label == %@", "閉じる")), in: app)
        XCTAssertTrue(app.staticTexts["browser-results"].waitForNonExistence(timeout: 20))
    }
    private func options(_ app: XCUIApplication) {
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-options-open"), in: app)
        _ = waitForTestControl(app.buttons.matching(identifier: "browser-options-save"), in: app)
    }
    private func setOption(_ identifier: String, enabled: Bool, in app: XCUIApplication) {
        setTestSwitch(app.switches.matching(identifier: identifier), enabled: enabled, in: app)
    }
    func testFlagNameCancelEmptySaveAndRelaunchKeepNumericSearch() {
        let app = makeApplication(); app.launchArguments = []; app.launch()
        browser("", count: 0, in: app)
        func openNames(draftNotes: Bool = false) {
            options(app)
            if draftNotes { setOption("browser-options-notes", enabled: true, in: app) }
            tapTestControl(app.buttons.matching(identifier: "flag-names-open"), in: app, form: app.collectionViews["browser-options-form"])
        }
        func editRed(_ name: String) {
            tapTestControl(app.buttons.matching(identifier: "flag-name-1"), in: app)
            tapTestControl(app.buttons.matching(identifier: "flag-name-clear"), in: app)
            if !name.isEmpty {
                _ = typeInEmptyTestField(app.textFields.matching(identifier: "flag-name-text"), text: name, in: app)
            }
        }
        func expectRed(_ name: String) {
            guard let red = waitForTestControl(app.buttons.matching(identifier: "flag-name-1"), in: app, purpose: .observation) else { return }
            XCTAssertEqual(red.label, name, app.debugDescription)
        }
        openNames(draftNotes: true); expectRed("赤")
        editRed("CancelledFlag")
        tapTestControl(app.buttons.matching(identifier: "flag-name-cancel"), in: app)
        expectRed("赤")
        editRed("")
        tapTestControl(app.buttons.matching(identifier: "flag-name-save"), in: app)
        expectRed("赤")
        editRed("PriorityFlag")
        tapTestControl(app.buttons.matching(identifier: "flag-name-save"), in: app)
        expectRed("PriorityFlag")
        capture("Flag name saved without changing flag code", in: app)
        tapTestControl(app.buttons.matching(identifier: "flag-names-close"), in: app)
        guard let draft = waitForTestControl(app.switches.matching(identifier: "browser-options-notes"), in: app, purpose: .observation) else { return }
        XCTAssertEqual(draft.value as? String, "1", "Returning from flag names must retain the unsaved options draft")
        tapTestControl(app.buttons.matching(identifier: "browser-options-cancel"), in: app)
        closeBrowser(app)
        app.terminate(); app.launch()
        browser("", count: 0, in: app)
        openNames(); expectRed("PriorityFlag")
        capture("Flag name retained after relaunch", in: app)
        tapTestControl(app.buttons.matching(identifier: "flag-names-close"), in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-options-cancel"), in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-filter-flags"), in: app)
        capture("Renamed native flag submenu", in: app)
        guard let renamed = waitForTestControl(menuActions(titles: ["PriorityFlag"], in: app), in: app) else { return }
        XCTAssertEqual(renamed.label, "PriorityFlag")
        tapTestMenuAction(titles: ["PriorityFlag"], in: app)
        guard let results = waitForTestControl(app.staticTexts.matching(identifier: "browser-results"), in: app, purpose: .observation) else { return }
        let numericSearch = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in results.value as? String == "flag:1" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [numericSearch], timeout: 20), .completed, app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testBrowserTruncationCancelsSavesAndRestoresFullRowsAfterRelaunch() {
        let app = makeApplication(); app.launchArguments = []; app.launch()
        addNote("Long browser content " + Array(repeating: "readableword", count: 60).joined(separator: " "), in: app)
        browser("", count: 1, in: app)
        let frontQuery = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-front-"))
        guard let front = waitForTestControl(frontQuery, in: app, purpose: .observation) else { return }
        let fullHeight = front.frame.height
        XCTAssertGreaterThan(fullHeight, 80)
        capture("Browser full row by default", in: app)
        options(app)
        guard let toggle = waitForTestControl(app.switches.matching(identifier: "browser-options-truncate"), in: app) else { return }
        XCTAssertEqual(toggle.value as? String, "0")
        setOption("browser-options-truncate", enabled: true, in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-options-cancel"), in: app)
        guard let unchanged = waitForTestControl(frontQuery, in: app, purpose: .observation) else { return }
        XCTAssertGreaterThanOrEqual(unchanged.frame.height, fullHeight - 2)
        options(app)
        guard let cancelled = waitForTestControl(app.switches.matching(identifier: "browser-options-truncate"), in: app) else { return }
        XCTAssertEqual(cancelled.value as? String, "0")
        setOption("browser-options-truncate", enabled: true, in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-options-save"), in: app)
        let collapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in front.exists && front.frame.height < fullHeight - 20 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 20), .completed, app.debugDescription)
        let collapsedHeight = front.frame.height
        capture("Browser row truncated to three lines", in: app)
        app.terminate(); app.launch()
        browser("", count: 1, in: app)
        guard let restored = waitForTestControl(frontQuery, in: app, purpose: .observation) else { return }
        XCTAssertLessThanOrEqual(restored.frame.height, collapsedHeight + 2)
        options(app)
        guard let persisted = waitForTestControl(app.switches.matching(identifier: "browser-options-truncate"), in: app) else { return }
        XCTAssertEqual(persisted.value as? String, "1")
        setOption("browser-options-truncate", enabled: false, in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-options-save"), in: app)
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in restored.exists && restored.frame.height > collapsedHeight + 20 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 20), .completed, app.debugDescription)
    }
    func testBrowserSearchOptionsCancelSaveAndDefaultRespectExplicitSearch() {
        let app = makeApplication(); app.launchArguments = []; app.launch()
        addNote("café", in: app)
        browser("cafe", count: 0, in: app)
        func editOptions() {
            setOption("browser-options-notes", enabled: true, in: app)
            setOption("browser-options-ignore-accents", enabled: true, in: app)
            _ = typeInEmptyTestField(app.textFields.matching(identifier: "browser-options-default-search"), text: "cafe", in: app)
        }
        options(app); editOptions()
        tapTestControl(app.buttons.matching(identifier: "browser-options-cancel"), in: app)
        guard let results = waitForTestControl(app.staticTexts.matching(identifier: "browser-results"), in: app, purpose: .observation) else { return }
        XCTAssertTrue(results.label.contains("0枚"), app.debugDescription)
        options(app); editOptions()
        tapTestControl(app.buttons.matching(identifier: "browser-options-save"), in: app)
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            results.exists && results.label.contains("1ノート") && results.value as? String == "cafe"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 20), .completed, app.debugDescription)
        closeBrowser(app)
        app.terminate(); app.launch()
        tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-open"), in: app)
        guard let initial = waitForTestControl(app.staticTexts.matching(identifier: "browser-results"), in: app, purpose: .observation) else { return }
        let defaultApplied = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in initial.value as? String == "cafe" && initial.label.contains("1ノート") }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [defaultApplied], timeout: 20), .completed, app.debugDescription)
        capture("Browser saved search and notes mode after relaunch", in: app)
        closeBrowser(app)
        browser("", count: 1, notesMode: true, in: app)
        capture("Browser explicit empty search overrides default", in: app)
    }
    func testBrowserSearchCreatesFilteredDeckAndEmptySearchCancelKeepsCollection() {
        let app = makeApplication(); app.launchArguments = []; app.launch()
        addNote("Browser Needle", in: app)
        addNote("Browser Outside", in: app)
        browser("", count: 2, in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-create-filtered"), in: app)
        guard typeInEmptyTestField(app.textFields.matching(identifier: "filtered-search"), text: "EmptySearchSentinel", in: app) != nil else { return }
        tapTestControl(app.buttons.matching(identifier: "filtered-cancel"), in: app)
        closeBrowser(app)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier MATCHES %@", "deck-[0-9]+" )).count, 1)
        let search = "\"Browser Needle\" -tag:excluded"
        browser(search, count: 1, in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-create-filtered"), in: app)
        guard let query = waitForTestControl(app.textFields.matching(identifier: "filtered-search"), in: app, purpose: .observation),
              let name = waitForTestControl(app.textFields.matching(identifier: "filtered-name"), in: app, purpose: .observation) else { return }
        XCTAssertEqual(query.value as? String, search)
        let deckName = name.value as? String ?? ""
        XCTAssertFalse(deckName.isEmpty)
        tapTestControl(app.buttons.matching(identifier: "filtered-build"), in: app)
        XCTAssertTrue(app.textFields["filtered-search"].waitForNonExistence(timeout: 30), app.debugDescription)
        closeBrowser(app)
        let deck = app.buttons.matching(NSPredicate(format: "identifier MATCHES %@ AND label BEGINSWITH %@", "deck-[0-9]+", deckName))
        guard let built = waitForTestControl(deck, in: app) else { return }
        XCTAssertTrue(built.label.hasSuffix("、1、0、0"), "The inherited second search must not pull in the other card: " + built.label)
        tapTestControl(deck, in: app)
        XCTAssertTrue(app.buttons["reveal"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.webViews.staticTexts["Browser Needle"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testBrowserGlobalFindReplaceShowsAllScopeAndPersistsChanges() {
        let app = makeApplication(); app.launchArguments = []; app.launch()
        addNote("ReplaceOriginal One", in: app)
        addNote("ReplaceOriginal Two", in: app)
        browser("ReplaceOriginal", count: 2, in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-find-replace"), in: app)
        guard let scope = waitForTestControl(app.staticTexts.matching(identifier: "replace-scope"), in: app, purpose: .observation) else { return }
        XCTAssertEqual(scope.label, "対象: すべてのノート")
        guard let search = tapTestControl(app.textFields.matching(identifier: "replace-search"), in: app) else { return }
        search.typeText("ReplaceOriginal")
        guard let replacement = tapTestControl(app.textFields.matching(identifier: "replace-replacement"), in: app) else { return }
        replacement.typeText("ReplaceUpdated")
        tapTestControl(app.buttons.matching(identifier: "replace-submit"), in: app)
        guard waitForTestControl(app.staticTexts.matching(NSPredicate(format: "label == %@", "すべてのノートを対象に置換しますか？")), in: app, purpose: .observation) != nil else { return }
        tapTestControl(app.buttons.matching(NSPredicate(format: "label == %@", "置換する")), in: app)
        guard let result = waitForTestControl(app.staticTexts.matching(identifier: "replace-result"), in: app, purpose: .observation) else { return }
        XCTAssertEqual(result.label, "2件を変更しました。")
        capture("Global replacement committed", in: app)
        tapTestControl(app.buttons.matching(identifier: "replace-close"), in: app)
        closeBrowser(app)
        app.terminate(); app.launch()
        browser("ReplaceUpdated", count: 2, in: app)
        capture("Replacement persisted after relaunch", in: app)
        closeBrowser(app)
        browser("ReplaceOriginal", count: 0, in: app)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
