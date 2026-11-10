import XCTest

/// Isolate native input from APKG handoff, deck creation and card movement.
final class BrowserFilterInputFlowTests: StudyFlowTestSupport {
    private func nativeEvidence(_ app: XCUIApplication) -> String {
        let state = app.staticTexts.matching(identifier: "browser-native-input-state")
        return state.count == 1 ? String(describing: state.element.value) : "Native filter input state unavailable"
    }

    private func verifyScope(initialQuery: String, replacement: String? = nil) throws {
        let app = makeApplication()
        app.launchArguments = ["--uitest-browser-input-trace"]
        app.launch()
        tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-open"), in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestMenuAction(titles: ["検索条件を編集"], in: app)
        let query = app.textFields.matching(identifier: "search-filters-query")
        if !initialQuery.isEmpty { typeInEmptyTestField(query, text: initialQuery, in: app) }
        if let replacement { replaceTestField(query, expected: initialQuery, with: replacement, in: app) }
        let scope = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search-filters-deck-"))
        guard let row = waitForTestControl(scope, in: app, purpose: .observation) else { return }
        let identifier = row.identifier
        let deckName = row.label
        XCTAssertFalse(deckName.isEmpty, "The actual sole deck must expose its name")
        let evidence = XCTAttachment(string: nativeEvidence(app) + "\n" + app.debugDescription)
        evidence.name = "Before isolated deck switch"; evidence.lifetime = .keepAlways; add(evidence)
        guard setTestSwitch(scope, enabled: true, in: app, failureContext: { self.nativeEvidence(app) }) else { return }
        tapTestControl(app.buttons.matching(identifier: "search-filters-apply"), in: app)
        let text = replacement ?? initialQuery
        requireTestCondition("Selected native deck reaches the compiled search", in: app) {
            let results = app.staticTexts.matching(identifier: "browser-results")
            guard results.count == 1, let resolved = results.element.value as? String else { return false }
            return app.buttons.matching(identifier: "search-filters-apply").count == 0
                && resolved.contains("deck:") && resolved.contains(deckName) && (text.isEmpty || resolved.contains(text))
        }
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestMenuAction(titles: ["検索条件を編集"], in: app)
        let persisted = app.switches.matching(identifier: identifier)
        requireTestCondition("Reopened native deck switch retains its selected value", in: app) {
            persisted.count == 1 && persisted.element.value as? String == "1"
        }
        guard setTestSwitch(persisted, enabled: false, in: app, failureContext: { self.nativeEvidence(app) }) else { return }
        tapTestControl(app.buttons.matching(identifier: "search-filters-apply"), in: app)
        requireTestCondition("Clearing isolated native scope preserves literal input", in: app) {
            let results = app.staticTexts.matching(identifier: "browser-results")
            return app.buttons.matching(identifier: "search-filters-apply").count == 0
                && results.count == 1 && results.element.value as? String == text
        }
    }

    func testNativeDeckSwitchWithoutTextEditing() throws {
        try verifyScope(initialQuery: "")
    }

    func testNativeDeckSwitchAfterTypingText() throws {
        try verifyScope(initialQuery: "row")
    }

    func testNativeDeckSwitchAfterReplacingText() throws {
        try verifyScope(initialQuery: "row0", replacement: "row")
    }
}
