import XCTest

final class BrowserToolsFlowTests: StudyFlowTestSupport {
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
    private func browser(_ search: String, count: Int, in app: XCUIApplication) {
        var url = URLComponents(string: "studyclient://x-callback-url/browser")!
        url.queryItems = [URLQueryItem(name: "search", value: search)]
        app.open(url.url!)
        let results = app.staticTexts.matching(identifier: "browser-results")
        guard let state = waitForTestControl(results, in: app, purpose: .observation) else { return }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            state.value as? String == search && state.label.contains("\(count)枚")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, app.debugDescription)
    }
    private func closeBrowser(_ app: XCUIApplication) {
        tapTestControl(app.navigationBars.buttons.matching(NSPredicate(format: "label == %@", "閉じる")), in: app)
        XCTAssertTrue(app.staticTexts["browser-results"].waitForNonExistence(timeout: 20))
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
        tapTestControl(app.buttons.matching(identifier: "replace-close"), in: app)
        closeBrowser(app)
        app.terminate(); app.launch()
        browser("ReplaceUpdated", count: 2, in: app)
        closeBrowser(app)
        browser("ReplaceOriginal", count: 0, in: app)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
