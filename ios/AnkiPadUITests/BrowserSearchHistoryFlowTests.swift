import XCTest

final class BrowserSearchHistoryFlowTests: BrowserSearchTestSupport {
    private func submit(_ text: String, replacing previous: String, in app: XCUIApplication) throws {
        let fields = app.navigationBars.matching(identifier: "カードブラウザー").searchFields
            .matching(NSPredicate(format: "label == %@", "検索（deck:、tag:、is:due など）"))
        let field: XCUIElement
        if previous.isEmpty { field = try XCTUnwrap(typeInEmptyTestField(fields, text: text, in: app)) }
        else { field = try XCTUnwrap(replaceTestField(fields, expected: previous, with: text, in: app)) }
        field.typeText("\n")
        requireTestCondition("Explicit search submitted", in: app) {
            let status = app.staticTexts.matching(identifier: "browser-results")
            return status.count == 1 && status.element.value as? String == text
        }
    }
    private func openHistory(_ app: XCUIApplication) {
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestMenuAction(titles: ["最近の検索"], in: app)
        _ = waitForTestControl(app.buttons.matching(identifier: "browser-history-close"), in: app)
    }
    private func closeHistory(_ app: XCUIApplication) {
        tapTestControl(app.buttons.matching(identifier: "browser-history-close"), in: app)
        requireTestCondition("History dismissed", in: app) { app.buttons.matching(identifier: "browser-history-close").count == 0 }
    }
    private func expectHistory(_ expected: [String], in app: XCUIApplication) {
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-history-query-"))
        requireTestCondition("Exact recent searches in MRU order", in: app) {
            rows.count == expected.count && rows.allElementsBoundByIndex.map(\.label) == expected
        }
    }
    func testCommittedSearchHistoryReuseCancelAndRelaunch() throws {
        let (app, _) = try fixture()
        openHistory(app); expectHistory([], in: app); closeHistory(app)
        try submit("row0", replacing: "", in: app); expectRows([0], in: app)
        try submit("row1", replacing: "row0", in: app); expectRows([1], in: app)
        openHistory(app); expectHistory(["row1", "row0"], in: app)
        closeHistory(app); expectRows([1], in: app)
        XCTAssertEqual(app.staticTexts["browser-results"].value as? String, "row1")
        openHistory(app)
        let query = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "browser-history-query-", "row0"))
        tapTestControl(query, in: app)
        requireTestCondition("History selection applies and closes", in: app) { app.buttons.matching(identifier: "browser-history-close").count == 0 }
        expectRows([0], in: app)
        openHistory(app); expectHistory(["row0", "row1"], in: app); closeHistory(app)
        tapTestControl(app.navigationBars.buttons.matching(NSPredicate(format: "label == %@", "閉じる")), in: app)
        app.terminate(); app.launchArguments = []; app.launch()
        openBrowser("", in: app); expectRows([0, 1, 2, 3, 4], in: app)
        openHistory(app); expectHistory(["row0", "row1"], in: app)
        closeHistory(app); expectRows([0, 1, 2, 3, 4], in: app)
    }

    func testDeletingOneRecentSearchPreservesQueryCardsAndOtherEntryAfterRelaunch() throws {
        let (app, _) = try fixture()
        try submit("row0", replacing: "", in: app)
        try submit("row1", replacing: "row0", in: app)
        expectRows([1], in: app)
        openHistory(app); expectHistory(["row1", "row0"], in: app)
        let recent = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@",
                                                     "browser-history-query-", "row1"))
        guard let row = waitForTestControl(recent, in: app) else { return }
        row.swipeLeft(velocity: .slow)
        let delete = app.collectionViews.matching(identifier: "browser-history-list").buttons
            .matching(NSPredicate(format: "label IN %@", ["Delete", "削除"]))
        tapTestControl(delete, in: app, keyboard: .keep)
        expectHistory(["row0"], in: app)
        closeHistory(app); expectRows([1], in: app)
        XCTAssertEqual(app.staticTexts["browser-results"].value as? String, "row1")
        app.terminate(); app.launchArguments = []; app.launch()
        openBrowser("", in: app); expectRows([0, 1, 2, 3, 4], in: app)
        openHistory(app); expectHistory(["row0"], in: app)
        closeHistory(app); expectRows([0, 1, 2, 3, 4], in: app)
    }

    func testClearingRecentSearchesCanCancelAndPersistsWithoutChangingCards() throws {
        let (app, _) = try fixture()
        try submit("row0", replacing: "", in: app)
        try submit("row1", replacing: "row0", in: app)
        expectRows([1], in: app)
        openHistory(app); expectHistory(["row1", "row0"], in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-history-clear"), in: app)
        dismissTestPopover(in: app)
        expectHistory(["row1", "row0"], in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-history-clear"), in: app)
        tapTestAlertAction("browser-history-clear-confirm", in: app.popovers.sheets, application: app)
        expectHistory([], in: app)
        let clear = app.buttons.matching(identifier: "browser-history-clear")
        guard let emptyClear = waitForTestControl(clear, in: app, purpose: .observation) else { return }
        XCTAssertFalse(emptyClear.isEnabled)
        closeHistory(app); expectRows([1], in: app)
        XCTAssertEqual(app.staticTexts["browser-results"].value as? String, "row1")
        app.terminate(); app.launchArguments = []; app.launch()
        openBrowser("", in: app); expectRows([0, 1, 2, 3, 4], in: app)
        openHistory(app); expectHistory([], in: app)
        guard let persistedClear = waitForTestControl(clear, in: app, purpose: .observation) else { return }
        XCTAssertFalse(persistedClear.isEnabled)
        closeHistory(app); expectRows([0, 1, 2, 3, 4], in: app)
    }
}
