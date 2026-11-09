import XCTest

class BrowserSearchTestSupport: StudyFlowTestSupport {
    func fixture(extraArguments: [String] = []) throws -> (XCUIApplication, String) {
        let bundle = Bundle(for: Self.self)
        let source = try XCTUnwrap(bundle.url(forResource: "field-search", withExtension: "apkg", subdirectory: "ReceivedFixtures"))
        let manifest = try XCTUnwrap(bundle.url(forResource: "field-search", withExtension: "json", subdirectory: "ReceivedFixtures"))
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        let back = try XCTUnwrap(metadata["back"] as? String)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appendingPathComponent("fields.apkg")
        try Data(contentsOf: source).write(to: copy)
        let app = makeApplication(); app.launchArguments = extraArguments; app.launch()
        _ = waitForTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        app.open(copy)
        tapTestControl(app.buttons.matching(identifier: "incoming-import-confirm"), in: app)
        requireTestCondition("Field fixture import closes confirmation", in: app) {
            app.buttons.matching(identifier: "incoming-import-confirm").count == 0
                && app.buttons.matching(identifier: "collection-menu").count == 1
        }
        openBrowser("", in: app)
        expectRows([0, 1, 2, 3, 4], in: app)
        return (app, back)
    }
    func openBrowser(_ search: String, in app: XCUIApplication) {
        var url = URLComponents(string: "studyclient://x-callback-url/browser")!
        url.queryItems = [URLQueryItem(name: "search", value: search)]
        app.open(url.url!)
        requireTestCondition("Browser receives requested field fixture search", in: app) {
            let results = app.staticTexts.matching(identifier: "browser-results")
            return results.count == 1 && results.element.value as? String == search
        }
    }
    func expectRows(_ indices: [Int], in app: XCUIApplication) {
        guard requireTestCondition("Field-search result count \(indices.count)", in: app, condition: {
            let status = app.staticTexts.matching(identifier: "browser-results")
            return app.buttons.matching(identifier: "field-search-apply").count == 0
                && status.count == 1 && status.element.label.hasPrefix("\(indices.count)枚")
        }) else { return }
        let lists = app.collectionViews.matching(identifier: "browser-card-list")
        guard let list = waitForTestControl(lists, in: app, purpose: .observation) else { return }
        var identifiers = Set<String>()
        // Native List virtualizes rows outside the sheet. Prove every expected
        // value through the shared reveal/unique resolver and the total count.
        for index in indices {
            let row = lists.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@",
                                                            "browser-front-", "row" + String(index)))
            guard let value = waitForTestControl(row, in: app, form: list, purpose: .observation) else { return }
            XCTAssertTrue(identifiers.insert(value.identifier).inserted, "Each expected row needs a distinct card identity")
        }
        XCTAssertEqual(identifiers.count, indices.count)
        if let first = indices.first {
            let row = lists.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@",
                                                            "browser-front-", "row" + String(first)))
            revealFormControl(row.firstMatch, in: list, topInset: 40, bottomInset: 20,
                              maximumAttempts: 12, searchUpward: false)
            _ = waitForTestControl(row, in: app, purpose: .observation)
        } else {
            requireTestCondition("Empty result has no card rows", in: app) {
                lists.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-front-")).count == 0
            }
        }
    }
    func openFields(back: String, mode: String, text: String? = nil, combine: Bool = false, in app: XCUIApplication) {
        tapTestControl(app.buttons.matching(identifier: "browser-filter-menu"), in: app)
        tapTestMenuAction(titles: ["フィールドを検索"], in: app)
        tapTestControl(app.buttons.matching(identifier: "field-search-name"), in: app)
        tapTestMenuAction(titles: [back], in: app)
        tapTestControl(app.buttons.matching(identifier: "field-search-mode"), in: app)
        tapTestMenuAction(titles: [mode], in: app)
        if let text { typeInEmptyTestField(app.textFields.matching(identifier: "field-search-text"), text: text, in: app) }
        if combine { setTestSwitch(app.switches.matching(identifier: "field-search-combine"), enabled: true, in: app) }
    }
    func apply(_ app: XCUIApplication) {
        tapTestControl(app.buttons.matching(identifier: "field-search-apply"), in: app)
    }
}
