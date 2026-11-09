import XCTest

final class BrowserForgetFlowTests: StudyFlowTestSupport {
    private func fixture() throws -> XCUIApplication {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "browser-forget", withExtension: "apkg", subdirectory: "ReceivedFixtures"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("reset.apkg")
        try Data(contentsOf: source).write(to: file)
        let app = makeApplication()
        app.launchArguments = ["--uitest-browser-undo-trace"]
        app.launch()
        _ = waitForTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        app.open(file)
        tapTestControl(app.buttons.matching(identifier: "incoming-import-confirm"), in: app)
        requireTestCondition("Reviewed fixture import finishes", in: app) {
            app.buttons.matching(identifier: "incoming-import-confirm").count == 0 && app.buttons.matching(identifier: "collection-menu").count == 1
        }
        tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-open"), in: app)
        _ = waitForTestControl(app.staticTexts.matching(identifier: "browser-results"), in: app, purpose: .observation)
        return app
    }
    private func search(_ query: String, count: Int, notes: Bool = false, in app: XCUIApplication) {
        // XCUIApplication.open launches a new process on this runner. Undo
        // belongs to the current engine session, so search through the actual
        // native field while preserving the browser and collection lifetime.
        let status = app.staticTexts.matching(identifier: "browser-results")
        guard let current = waitForTestControl(status, in: app, purpose: .observation),
              let previous = current.value as? String else { return }
        if previous != query {
            let fields = app.navigationBars.matching(identifier: notes ? "ノートブラウザー" : "カードブラウザー").searchFields
                .matching(NSPredicate(format: "label == %@", "検索（deck:、tag:、is:due など）"))
            let field = previous.isEmpty
                ? typeInEmptyTestField(fields, text: query, in: app)
                : replaceTestField(fields, expected: previous, with: query, in: app)
            guard let field else { return }
            field.typeText("\n")
        }
        requireTestCondition("Reset result count \(count) for \(query)", in: app) {
            let status = app.staticTexts.matching(identifier: "browser-results")
            return status.count == 1 && status.element.value as? String == query && status.element.label.hasPrefix("\(count)" + (notes ? "ノート" : "枚"))
        }
    }
    private func openReset(count: Int, in app: XCUIApplication) {
        tapTestControl(app.buttons.matching(identifier: "browser-actions-menu"), in: app)
        tapTestMenuAction(titles: ["すべて選択"], in: app)
        requireTestCondition("Reset selection is committed", in: app) {
            let status = app.staticTexts.matching(identifier: "browser-results")
            return status.count == 1 && status.element.label.contains("1件選択中")
        }
        tapTestControl(app.buttons.matching(identifier: "browser-actions-menu"), in: app)
        tapTestMenuAction(titles: ["新規カードに戻す"], in: app)
        _ = waitForTestControl(app.buttons.matching(identifier: "browser-forget-apply"), in: app)
        requireTestCondition("Reset confirms actual expanded card count", in: app) {
            let label = app.staticTexts.matching(identifier: "browser-forget-count")
            return label.count == 1 && label.element.label == "\(count)枚"
        }
    }
    private func nativeState(_ app: XCUIApplication) -> String {
        let query = app.staticTexts.matching(identifier: "browser-forget-native-state")
        guard let state = waitForTestControl(query, in: app, keyboard: .keep, purpose: .observation) else { return "Native reset diagnostic missing" }
        return state.value as? String ?? "Native reset diagnostic value missing"
    }
    private func setOption(_ identifier: String, enabled: Bool, in app: XCUIApplication) {
        let evidence = XCTAttachment(string: nativeState(app))
        evidence.name = "Before " + identifier
        evidence.lifetime = .keepAlways
        add(evidence)
        setTestSwitch(app.switches.matching(identifier: identifier), enabled: enabled, in: app,
                      failureContext: { self.nativeState(app) })
    }
    private func expectOption(_ identifier: String, enabled: Bool, in app: XCUIApplication) {
        let row = app.switches.matching(identifier: identifier)
        guard waitForTestControl(row, in: app, purpose: .observation) != nil else { return }
        let children = row.children(matching: .switch)
        let native = children.count > 0 ? children : row
        guard let control = waitForTestControl(native, in: app, purpose: .observation) else { return }
        requireTestCondition("Stored reset option \(identifier)", in: app) { control.value as? String == (enabled ? "1" : "0") }
    }
    private func undo(in app: XCUIApplication) {
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestMenuAction(titles: ["取り消す"], in: app)
    }
    func testCardResetCancelOptionsPersistAndUndoLeavesSiblingReviewed() throws {
        let app = try fixture()
        let target = "row0 card:\"Reset Forward\""
        search(target, count: 1, in: app)
        openReset(count: 1, in: app)
        setOption("browser-forget-restore", enabled: false, in: app)
        setOption("browser-forget-counts", enabled: true, in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-forget-cancel"), in: app)
        search("row0 is:review", count: 2, in: app)
        search(target, count: 1, in: app)
        openReset(count: 1, in: app)
        expectOption("browser-forget-restore", enabled: true, in: app)
        expectOption("browser-forget-counts", enabled: false, in: app)
        setOption("browser-forget-restore", enabled: false, in: app)
        setOption("browser-forget-counts", enabled: true, in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-forget-apply"), in: app)
        requireTestCondition("Successful reset clears selection", in: app) {
            let status = app.staticTexts.matching(identifier: "browser-results")
            return app.buttons.matching(identifier: "browser-forget-apply").count == 0 && status.count == 1 && status.element.label.contains("0件選択中")
        }
        search("row0 is:new", count: 1, in: app)
        search("row0 is:review", count: 1, in: app)
        undo(in: app)
        search("row0 is:review", count: 2, in: app)
        search(target, count: 1, in: app)
        openReset(count: 1, in: app)
        expectOption("browser-forget-restore", enabled: false, in: app)
        expectOption("browser-forget-counts", enabled: true, in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-forget-cancel"), in: app)
    }
    func testNoteResetExpandsOnlySelectedNoteAndUndoRestoresBothCards() throws {
        let app = try fixture()
        search("row0", count: 2, in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestMenuAction(titles: ["ブラウザーの設定"], in: app)
        _ = waitForTestControl(app.buttons.matching(identifier: "browser-options-save"), in: app)
        setTestSwitch(app.switches.matching(identifier: "browser-options-notes"), enabled: true, in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-options-save"), in: app)
        search("row0", count: 1, notes: true, in: app)
        openReset(count: 2, in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-forget-apply"), in: app)
        requireTestCondition("Note reset closes its sheet", in: app) { app.buttons.matching(identifier: "browser-forget-apply").count == 0 }
        search("row0 is:new", count: 1, notes: true, in: app)
        search("row1 is:review", count: 1, notes: true, in: app)
        undo(in: app)
        search("row0 is:review", count: 1, notes: true, in: app)
        search("row0 is:new", count: 0, notes: true, in: app)
    }
}
