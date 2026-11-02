import XCTest

class BrowserSearchTestSupport: StudyFlowTestSupport {
    func fixture() throws -> (XCUIApplication, String) {
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
        let app = makeApplication(); app.launchArguments = []; app.launch()
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
        let expected = Set(indices.map { "row" + String($0) })
        let rows = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-front-"))
        requireTestCondition("Exact field-search result rows \(indices)", in: app) {
            let status = app.staticTexts.matching(identifier: "browser-results")
            return app.buttons.matching(identifier: "field-search-apply").count == 0
                && status.count == 1 && status.element.label.hasPrefix("\(indices.count)枚")
                && rows.count == expected.count && Set(rows.allElementsBoundByIndex.map(\.label)) == expected
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
