import XCTest

/// Isolate native input from APKG handoff, deck creation and card movement.
final class BrowserFilterInputFlowTests: StudyFlowTestSupport {
    private func nativeEvidence(_ app: XCUIApplication) -> String {
        let state = app.staticTexts.matching(identifier: "browser-native-input-state")
        return state.count == 1 ? String(describing: state.element.value) : "Native filter input state unavailable"
    }

    private func createScopeDeck(in app: XCUIApplication) throws -> String {
        var identifier = ""
        // The engine can hide an empty default deck after another is created.
        // Two named decks keep a real preceding row in the filter form.
        for name in ["Input First", "Input Scope"] {
            tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
            tapTestMenuAction(titles: ["デッキを作成"], in: app)
            let prompt = app.alerts.matching(identifier: "デッキを作成")
            typeInEmptyTestField(prompt.textFields, text: name, in: app)
            tapTestAlertAction(titles: ["保存"], in: prompt, application: app)
            let deck = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "deck-", name))
            identifier = try XCTUnwrap(waitForTestControl(deck, in: app)).identifier
        }
        return identifier
    }

    private func verifyScope(initialQuery: String, replacement: String? = nil,
                             multipleDecks: Bool = false, cycleEditing: Bool = false) throws {
        let app = makeApplication()
        app.launchArguments = ["--uitest-browser-input-trace"]
        app.launch()
        _ = waitForTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        let targetDeck = multipleDecks ? try createScopeDeck(in: app) : nil
        tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-open"), in: app)
        if cycleEditing {
            let editing = app.buttons.matching(identifier: "browser-edit-mode")
            let normalLabel = try XCTUnwrap(waitForTestControl(editing, in: app)).label
            tapTestControl(editing, in: app)
            requireTestCondition("Native edit mode changes the action label", in: app) {
                editing.count == 1 && editing.element.label != normalLabel
            }
            tapTestControl(editing, in: app)
            requireTestCondition("Native edit mode returns to its initial state", in: app) {
                editing.count == 1 && editing.element.label == normalLabel
            }
        }
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestMenuAction(titles: ["検索条件を編集"], in: app)
        let query = app.textFields.matching(identifier: "search-filters-query")
        if !initialQuery.isEmpty { typeInEmptyTestField(query, text: initialQuery, in: app) }
        if let replacement { replaceTestField(query, expected: initialQuery, with: replacement, in: app) }
        let scope: XCUIElementQuery
        if let targetDeck { scope = app.switches.matching(identifier: "search-filters-" + targetDeck) }
        else { scope = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search-filters-deck-")) }
        guard let row = waitForTestControl(scope, in: app, purpose: .observation) else { return }
        let identifier = row.identifier
        let deckName = row.label
        if multipleDecks {
            let preceding = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@", "search-filters-deck-", identifier))
            requireTestCondition("Target has an actual preceding visible deck row", in: app) {
                preceding.count >= 1 && preceding.allElementsBoundByIndex.contains { $0.isHittable && $0.frame.midY < row.frame.minY }
            }
        }
        XCTAssertFalse(deckName.isEmpty, "The target deck must expose its name")
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

    func testLaterNativeDeckSwitchAfterReplacingText() throws {
        try verifyScope(initialQuery: "row0", replacement: "row", multipleDecks: true)
    }

    func testNativeDeckSwitchAfterLeavingEditMode() throws {
        try verifyScope(initialQuery: "row0", replacement: "row", cycleEditing: true)
    }

    func testLaterNativeDeckSwitchAfterLeavingEditMode() throws {
        try verifyScope(initialQuery: "row0", replacement: "row", multipleDecks: true, cycleEditing: true)
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
