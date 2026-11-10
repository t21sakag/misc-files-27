import XCTest

class BrowserSearchTestSupport: StudyFlowTestSupport {
    private var observedFrontIdentifiers: [String: [Int: String]] = [:]
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
        if extraArguments.contains("--uitest-browser-input-trace") {
            guard requireTestCondition("Field fixture incoming confirmation", in: app, timeout: 20,
                                       failureContext: {
                let diagnostic = app.staticTexts.matching(identifier: "incoming-native-state")
                return diagnostic.count == 1 ? String(describing: diagnostic.element.value) : "Incoming diagnostic unavailable"
            }, condition: {
                app.buttons.matching(identifier: "incoming-import-confirm").count == 1
            }) else { return (app, back) }
        }
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
        guard waitForTestControl(lists, in: app, purpose: .observation) != nil else { return }
        let namespace = app.launchEnvironment["ANKIPAD_UI_TEST_NAMESPACE"] ?? String(describing: ObjectIdentifier(app))
        let expected = Set(indices)
        if expected.isEmpty {
            requireTestCondition("Empty result has no card rows", in: app) {
                lists.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-front-")).count == 0
            }
            return
        }
        let firstIndex = indices[0]
        var seen: [Int: String] = [:]
        var lastPage = ""
        func inspect(_ cells: [XCUIElement], returningToFirst: Bool) -> (ready: Bool, complete: Bool, fingerprint: String) {
            var page: [(index: Int, identifier: String, frame: CGRect)] = []
            for cell in cells {
                let fronts = cell.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-front-")).allElementsBoundByIndex
                if fronts.isEmpty { continue }
                guard fronts.count == 1 else {
                    lastPage = "Mounted cell has multiple front elements"; return (false, false, lastPage)
                }
                let front = fronts[0]
                guard front.isHittable else { continue }
                let label = front.label, identifier = front.identifier, frame = front.frame
                guard identifier.hasPrefix("browser-front-"),
                      !identifier.dropFirst("browser-front-".count).isEmpty,
                      frame.width > 0, frame.height > 0 else {
                    lastPage = "Incomplete mounted front snapshot for " + label; return (false, false, lastPage)
                }
                guard label.hasPrefix("row"), let index = Int(label.dropFirst(3)), label == "row" + String(index) else {
                    lastPage = "Unexpected mounted front: " + label; return (false, false, lastPage)
                }
                guard expected.contains(index), !page.contains(where: { $0.index == index || $0.identifier == identifier }) else {
                    lastPage = "Unexpected or duplicate mounted front: " + label; return (false, false, lastPage)
                }
                if let previous = self.observedFrontIdentifiers[namespace]?[index], previous != identifier {
                    lastPage = "Native card identity changed for " + label; return (false, false, lastPage)
                }
                page.append((index, identifier, frame))
            }
            lastPage = page.map { "row\($0.index):\($0.identifier):\($0.frame)" }.joined(separator: "|")
            for item in page {
                self.observedFrontIdentifiers[namespace, default: [:]][item.index] = item.identifier
                if expected.contains(item.index) { seen[item.index] = item.identifier }
            }
            guard Set(seen.values).count == seen.count else {
                lastPage = "Expected fronts share a native card identity"; return (false, false, lastPage)
            }
            let complete = returningToFirst
                ? page.contains { $0.index == firstIndex }
                : Set(seen.keys) == expected
            return (!page.isEmpty, complete, page.map { $0.identifier }.joined(separator: "|"))
        }
        let details = { "Expected: \(indices); observed: \(seen); page: \(lastPage)" }
        guard scanTestCollectionPages(lists, in: app, description: "all expected fixture cards", failureContext: details,
            inspect: { inspect($0, returningToFirst: false) }) else { return }
        XCTAssertEqual(seen.count, indices.count)
        _ = scanTestCollectionPages(lists, in: app, description: "first verified fixture card", failureContext: details,
            inspect: { inspect($0, returningToFirst: true) })
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
