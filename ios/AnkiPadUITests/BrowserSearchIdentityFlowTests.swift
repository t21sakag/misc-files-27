import XCTest

final class BrowserSearchIdentityFlowTests: BrowserSearchTestSupport {
    private let originalName = "Identity Scope A"

    private func closeBrowser(_ app: XCUIApplication) {
        let close = app.navigationBars.matching(identifier: "カードブラウザー").buttons
            .matching(NSPredicate(format: "label == %@", "閉じる"))
        tapTestControl(close, in: app)
        _ = waitForTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
    }

    private func openNativeBrowser(_ app: XCUIApplication) {
        tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-open"), in: app)
        _ = waitForTestControl(app.staticTexts.matching(identifier: "browser-results"), in: app, purpose: .observation)
    }

    private func openHistory(_ app: XCUIApplication) {
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestMenuAction(titles: ["最近の検索"], in: app)
        _ = waitForTestControl(app.buttons.matching(identifier: "browser-history-close"), in: app)
    }

    private func historyRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-history-query-"))
    }

    private func scopedHistory() throws -> (XCUIApplication, String) {
        let (app, _) = try fixture(extraArguments: ["--uitest-browser-input-trace"])
        closeBrowser(app)
        tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        tapTestMenuAction(titles: ["デッキを作成"], in: app)
        let create = app.alerts.matching(identifier: "デッキを作成")
        typeInEmptyTestField(create.textFields, text: originalName, in: app)
        tapTestAlertAction(titles: ["保存"], in: create, application: app)
        let deck = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                   "deck-", originalName))
        let row = try XCTUnwrap(waitForTestControl(deck, in: app))
        let deckIdentifier = row.identifier
        let deckID = String(deckIdentifier.dropFirst("deck-".count))
        XCTAssertNotNil(Int64(deckID))
        openNativeBrowser(app); expectRows([0, 1, 2, 3, 4], in: app)
        let fields = app.navigationBars.matching(identifier: "カードブラウザー").searchFields
            .matching(NSPredicate(format: "label == %@", "検索（deck:、tag:、is:due など）"))
        // Live filtering narrows the fixture without committing a raw-text
        // history entry before the structured request under test.
        _ = try XCTUnwrap(typeInEmptyTestField(fields, text: "row0", in: app))
        expectRows([0], in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-actions-menu"), in: app)
        tapTestMenuAction(titles: ["すべて選択"], in: app)
        requireTestCondition("One card selected for identity fixture", in: app) {
            let count = app.staticTexts.matching(identifier: "browser-results")
            return count.count == 1 && count.element.label.contains("1件選択中")
        }
        tapTestControl(app.buttons.matching(identifier: "browser-actions-menu"), in: app)
        tapTestMenuAction(titles: ["デッキを移動"], in: app)
        tapTestAlertAction(titles: [originalName], in: app.popovers.sheets, application: app)
        requireTestCondition("Moving the fixture card clears selection", in: app) {
            let count = app.staticTexts.matching(identifier: "browser-results")
            return count.count == 1 && count.element.label.contains("0件選択中")
        }
        tapTestControl(app.buttons.matching(identifier: "browser-edit-mode"), in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestMenuAction(titles: ["検索条件を編集"], in: app)
        let form = try XCTUnwrap(waitForTestControl(app.collectionViews.matching(identifier: "search-filters-form"),
                                                  in: app, purpose: .observation))
        replaceTestField(app.textFields.matching(identifier: "search-filters-query"), expected: "row0", with: "row", in: app)
        let scope = app.switches.matching(identifier: "search-filters-deck-" + deckID)
        _ = try XCTUnwrap(waitForTestControl(scope, in: app, form: form, purpose: .observation))
        setTestSwitch(scope, enabled: true, in: app, failureContext: {
            let state = app.staticTexts.matching(identifier: "browser-native-input-state")
            let value = self.waitForTestControl(state, in: app, keyboard: .keep, purpose: .observation)
            return value?.value as? String ?? "Native search input diagnostic unavailable"
        })
        tapTestControl(app.buttons.matching(identifier: "search-filters-apply"), in: app)
        expectRows([0], in: app)
        closeBrowser(app)
        return (app, deckIdentifier)
    }

    func testStructuredHistoryResolvesRenamedDeckIDAfterRelaunch() throws {
        let (app, identifier) = try scopedHistory()
        let renamed = "Identity Scope Renamed"
        let deck = app.buttons.matching(identifier: identifier)
        let row = try XCTUnwrap(waitForTestControl(deck, in: app))
        row.press(forDuration: 1)
        tapTestMenuAction(titles: ["名前を変更"], in: app)
        let rename = app.alerts.matching(identifier: "デッキ名を変更")
        replaceTestField(rename.textFields, expected: originalName, with: renamed, in: app)
        tapTestAlertAction(titles: ["保存"], in: rename, application: app)
        requireTestCondition("Deck identity survives native rename", in: app) {
            deck.count == 1 && deck.element.label.contains(renamed)
        }
        app.terminate(); app.launchArguments = []; app.launch()
        _ = waitForTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        openNativeBrowser(app); expectRows([0, 1, 2, 3, 4], in: app)
        openHistory(app)
        let history = historyRows(app)
        requireTestCondition("Structured history resolves current deck name", in: app) {
            history.count == 1 && history.element.label.contains(renamed)
                && !history.element.label.contains(self.originalName)
        }
        tapTestControl(history, in: app)
        expectRows([0], in: app)
        let query = try XCTUnwrap(app.staticTexts["browser-results"].value as? String)
        XCTAssertTrue(query.contains(renamed))
        XCTAssertFalse(query.contains(originalName))
    }

    func testMissingHistoryDeckShowsErrorWithoutBroadeningCurrentSearch() throws {
        let (app, identifier) = try scopedHistory()
        let deck = app.buttons.matching(identifier: identifier)
        let row = try XCTUnwrap(waitForTestControl(deck, in: app))
        row.press(forDuration: 1)
        tapTestMenuAction(titles: ["削除"], in: app)
        tapTestAlertAction("deck-delete-confirm", in: app.popovers.sheets, application: app)
        requireTestCondition("Synthetic scope deck is deleted", in: app) { deck.count == 0 }
        openNativeBrowser(app); expectRows([1, 2, 3, 4], in: app)
        openHistory(app)
        let history = historyRows(app)
        requireTestCondition("Unresolvable history entry is retained", in: app) {
            history.count == 1 && history.element.label == "row"
        }
        tapTestControl(history, in: app)
        let error = app.alerts.matching(identifier: "検索できませんでした")
        _ = waitForTestControl(error, in: app, keyboard: .keep, purpose: .observation)
        tapTestAlertAction(titles: ["閉じる"], in: error, application: app)
        _ = waitForTestControl(app.buttons.matching(identifier: "browser-history-close"), in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-history-close"), in: app)
        expectRows([1, 2, 3, 4], in: app)
        XCTAssertEqual(app.staticTexts["browser-results"].value as? String, "")
    }
}
