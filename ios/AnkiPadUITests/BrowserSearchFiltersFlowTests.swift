import XCTest

final class BrowserSearchFiltersFlowTests: BrowserSearchTestSupport {
    private func openFilters(_ app: XCUIApplication) {
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestMenuAction(titles: ["検索条件を編集"], in: app)
        _ = waitForTestControl(app.buttons.matching(identifier: "search-filters-apply"), in: app)
    }
    private func setFlag(_ value: Int, enabled: Bool, in app: XCUIApplication) {
        let form = app.collectionViews.matching(identifier: "search-filters-form")
        guard let container = waitForTestControl(form, in: app, purpose: .observation) else { return }
        let flag = app.switches.matching(identifier: "search-filters-flag-\(value)")
        guard waitForTestControl(flag, in: app, form: container, purpose: .observation) != nil else { return }
        setTestSwitch(flag, enabled: enabled, in: app)
    }
    private func expectFlag(_ value: Int, enabled: Bool, in app: XCUIApplication) {
        guard let flag = waitForTestControl(app.switches.matching(identifier: "search-filters-flag-\(value)"), in: app, purpose: .observation) else { return }
        requireTestCondition("Structured flag \(value) restores its selection", in: app) {
            flag.value as? String == (enabled ? "1" : "0")
        }
    }
    private func applyFilters(_ app: XCUIApplication) {
        tapTestControl(app.buttons.matching(identifier: "search-filters-apply"), in: app)
        requireTestCondition("Structured filter editor closes after applying", in: app) {
            app.buttons.matching(identifier: "search-filters-apply").count == 0
        }
    }
    func testStructuredFilterORCancelFieldIntersectionAndClear() throws {
        let (app, back) = try fixture()
        openFilters(app)
        typeInEmptyTestField(app.textFields.matching(identifier: "search-filters-query"), text: "row", in: app)
        setFlag(0, enabled: true, in: app); setFlag(1, enabled: true, in: app)
        applyFilters(app); expectRows([0, 1, 2, 3, 4], in: app)
        let original = try XCTUnwrap(app.staticTexts["browser-results"].value as? String)
        XCTAssertTrue(original.contains("flag:0") && original.contains("flag:1"), "Both selected flags must remain in the actual engine query")
        openFilters(app)
        expectFlag(0, enabled: true, in: app); expectFlag(1, enabled: true, in: app)
        setFlag(0, enabled: false, in: app)
        tapTestControl(app.buttons.matching(identifier: "search-filters-cancel"), in: app)
        expectRows([0, 1, 2, 3, 4], in: app)
        XCTAssertEqual(app.staticTexts["browser-results"].value as? String, original)
        openFields(back: back, mode: "完全一致", text: "cat", combine: true, in: app)
        apply(app); expectRows([0], in: app)
        openFilters(app)
        expectFlag(0, enabled: true, in: app); expectFlag(1, enabled: true, in: app)
        let form = try XCTUnwrap(waitForTestControl(app.collectionViews.matching(identifier: "search-filters-form"), in: app, purpose: .observation))
        tapTestControl(app.buttons.matching(identifier: "search-filters-clear"), in: app, form: form)
        applyFilters(app); expectRows([0], in: app)
        let cleared = try XCTUnwrap(app.staticTexts["browser-results"].value as? String)
        XCTAssertFalse(cleared.contains("flag:"), "Clear filters must retain raw/field text while removing graphical flags")
        tapTestControl(app.navigationBars.buttons.matching(NSPredicate(format: "label == %@", "閉じる")), in: app)
        app.terminate(); app.launchArguments = []; app.launch()
        openBrowser("", in: app); expectRows([0, 1, 2, 3, 4], in: app)
    }
    private func browserSearchFields(_ app: XCUIApplication) -> XCUIElementQuery {
        app.navigationBars.matching(identifier: "カードブラウザー").searchFields
            .matching(NSPredicate(format: "label == %@", "検索（deck:、tag:、is:due など）"))
    }
    private func rawSearch(_ expected: String, in app: XCUIApplication) {
        guard let field = waitForTestControl(browserSearchFields(app), in: app, purpose: .observation) else { return }
        requireTestCondition("Raw editable text excludes graphical filter clauses", in: app) { field.value as? String == expected }
    }
    private func compiledSearch(containing terms: [String], in app: XCUIApplication) throws -> String {
        let results = app.staticTexts.matching(identifier: "browser-results")
        guard requireTestCondition("Compiled search contains every active criterion", in: app, condition: {
            guard results.count == 1, let value = results.element.value as? String else { return false }
            return terms.allSatisfy { value.contains($0) }
        }) else { throw NSError(domain: "SearchState", code: 1) }
        return try XCTUnwrap(results.element.value as? String)
    }
    private func setNewState(_ enabled: Bool, in app: XCUIApplication) {
        guard let form = waitForTestControl(app.collectionViews.matching(identifier: "search-filters-form"), in: app, purpose: .observation) else { return }
        let state = app.switches.matching(identifier: "search-filters-state-0")
        guard waitForTestControl(state, in: app, form: form, purpose: .observation) != nil else { return }
        setTestSwitch(state, enabled: enabled, in: app)
    }
    func testStructuredFiltersSurviveRawTypingAndFilterOnlyFieldAND() throws {
        let (app, back) = try fixture()
        openFilters(app); setFlag(1, enabled: true, in: app); applyFilters(app)
        _ = try compiledSearch(containing: ["flag:1"], in: app); expectRows([], in: app)
        // A filter-only request has empty editable text but is a valid AND base.
        openFields(back: back, mode: "完全一致", text: "cat", combine: true, in: app)
        apply(app)
        _ = try compiledSearch(containing: ["flag:1", "cat"], in: app); expectRows([], in: app)
        let field = try XCTUnwrap(waitForTestControl(browserSearchFields(app), in: app, purpose: .observation))
        let previous = try XCTUnwrap(field.value as? String)
        XCTAssertTrue(previous.contains("cat")); XCTAssertFalse(previous.contains("flag:"))
        let edited = try XCTUnwrap(replaceTestField(browserSearchFields(app), expected: previous, with: "row0", in: app))
        edited.typeText("\n")
        _ = try compiledSearch(containing: ["row0", "flag:1"], in: app); expectRows([], in: app)
        rawSearch("row0", in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-filter-chip-flags"), in: app)
        requireTestCondition("Removing one filter preserves raw text", in: app) {
            app.buttons.matching(identifier: "browser-filter-chip-flags").count == 0
                && app.staticTexts["browser-results"].value as? String == "row0"
        }
        expectRows([0], in: app); rawSearch("row0", in: app)
    }
    func testQuickFilterPreservesOtherCategoryAndTypedHistoryAfterRelaunch() throws {
        let (app, _) = try fixture()
        openFilters(app); setFlag(0, enabled: true, in: app); setNewState(true, in: app); applyFilters(app)
        _ = try compiledSearch(containing: ["flag:0", "is:new"], in: app); expectRows([0, 1, 2, 3, 4], in: app)
        let field = try XCTUnwrap(typeInEmptyTestField(browserSearchFields(app), text: "row1", in: app))
        field.typeText("\n")
        _ = try compiledSearch(containing: ["row1", "flag:0", "is:new"], in: app); expectRows([1], in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-filter-flags"), in: app)
        tapTestMenuAction(titles: ["赤"], in: app)
        let compiled = try compiledSearch(containing: ["row1", "flag:1", "is:new"], in: app)
        expectRows([], in: app); rawSearch("row1", in: app)
        tapTestControl(app.navigationBars.buttons.matching(NSPredicate(format: "label == %@", "閉じる")), in: app)
        app.terminate(); app.launchArguments = []; app.launch()
        openBrowser("", in: app); expectRows([0, 1, 2, 3, 4], in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestMenuAction(titles: ["最近の検索"], in: app)
        tapTestControl(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "browser-history-query-", compiled)), in: app)
        requireTestCondition("Typed history closes and restores the complete request", in: app) {
            app.buttons.matching(identifier: "browser-history-close").count == 0
                && app.staticTexts["browser-results"].value as? String == compiled
        }
        expectRows([], in: app); rawSearch("row1", in: app)
        _ = waitForTestControl(app.buttons.matching(identifier: "browser-filter-chip-flags"), in: app)
        _ = waitForTestControl(app.buttons.matching(identifier: "browser-filter-chip-states"), in: app)
    }
    func testSavedSearchAndFilteredDeckUseCompleteResolvedRequest() throws {
        let (app, _) = try fixture()
        openFilters(app)
        typeInEmptyTestField(app.textFields.matching(identifier: "search-filters-query"), text: "row1", in: app)
        setFlag(0, enabled: true, in: app); applyFilters(app)
        let compiled = try compiledSearch(containing: ["row1", "flag:0"], in: app)
        expectRows([1], in: app); rawSearch("row1", in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-create-filtered"), in: app)
        guard let inherited = waitForTestControl(app.textFields.matching(identifier: "filtered-search"), in: app, purpose: .observation) else { return }
        XCTAssertEqual(inherited.value as? String, compiled, "Filtered deck must receive raw text AND graphical filters")
        tapTestControl(app.buttons.matching(identifier: "filtered-cancel"), in: app)
        expectRows([1], in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestMenuAction(titles: ["保存した検索"], in: app)
        tapTestMenuAction(titles: ["この検索を保存"], in: app)
        let alert = app.alerts.matching(identifier: "検索を保存")
        typeInEmptyTestField(alert.textFields, text: "OwnedSearch", in: app)
        tapTestAlertAction(titles: ["保存"], in: alert, application: app)
        requireTestCondition("Saved search confirmation closes", in: app) { alert.count == 0 }
        tapTestControl(app.buttons.matching(identifier: "browser-filter-chip-flags"), in: app)
        requireTestCondition("Graphical filter removed before bookmark reuse", in: app) {
            app.buttons.matching(identifier: "browser-filter-chip-flags").count == 0
                && app.staticTexts["browser-results"].value as? String == "row1"
        }
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestMenuAction(titles: ["保存した検索"], in: app)
        tapTestMenuAction(titles: ["OwnedSearch"], in: app)
        requireTestCondition("Saved search restores its complete resolved query", in: app) {
            app.staticTexts["browser-results"].value as? String == compiled
        }
        expectRows([1], in: app); rawSearch(compiled, in: app)
        tapTestControl(app.navigationBars.buttons.matching(NSPredicate(format: "label == %@", "閉じる")), in: app)
        app.terminate(); app.launchArguments = []; app.launch()
        openBrowser("", in: app); expectRows([0, 1, 2, 3, 4], in: app)
    }

}
