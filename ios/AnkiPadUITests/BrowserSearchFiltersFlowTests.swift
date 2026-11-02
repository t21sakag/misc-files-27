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
}
