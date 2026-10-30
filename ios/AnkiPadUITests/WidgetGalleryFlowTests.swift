import XCTest

/// Exercise the OS gallery and the real remote widget process. A synthetic
/// in-app preview cannot prove registration, shared-group reads, or widgetURL.
final class WidgetGalleryFlowTests: StudyFlowTestSupport {
    private func capture(_ stage: String, in app: XCUIApplication) {
        XCTContext.runActivity(named: stage) { activity in
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = stage + " hierarchy"; hierarchy.lifetime = .keepAlways
            activity.add(hierarchy)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = stage; screenshot.lifetime = .keepAlways
            activity.add(screenshot)
        }
    }
    private func label(_ values: [String]) -> NSPredicate { NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern(values)) }
    private func tapChoice(_ values: [String], in app: XCUIApplication) {
        let menu = app.menuItems.matching(label(values)), buttons = app.buttons.matching(label(values))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (menu.count == 1 && menu.firstMatch.isHittable) || (buttons.count == 1 && buttons.firstMatch.isHittable)
        }, object: nil)
        guard XCTWaiter.wait(for: [ready], timeout: 20) == .completed else {
            capture("Missing foreground choice " + values[0], in: app)
            XCTFail("No unique foreground menu item/button: " + app.debugDescription); return
        }
        if menu.count == 1 && menu.firstMatch.isHittable { tapTestControl(menu, in: app, keyboard: .keep) }
        else { tapTestControl(buttons, in: app, keyboard: .keep) }
    }
    private func expectedCount(_ app: XCUIApplication) -> Int {
        let state = app.staticTexts["widget-snapshot-state"]
        var total: Int?
        let stored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard state.exists, let raw = state.value as? String, let data = raw.data(using: .utf8),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let profiles = root["profiles"] as? [[String: Any]],
                  let profile = profiles.first(where: { $0["id"] as? String == "default" }),
                  let collection = profile["collection"] as? [String: Any], let counts = collection["counts"] as? [String: Int] else { return false }
            total = (counts["new"] ?? 0) + (counts["learning"] ?? 0) + (counts["review"] ?? 0)
            return total != nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [stored], timeout: 30), .completed, app.debugDescription)
        XCTAssertGreaterThan(total ?? 0, 0, "The synthetic collection must have due cards")
        return total ?? 0
    }
    func testHomeGalleryAddsSummaryWithActualSharedCountsAndOpensApp() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture", "--uitest-widgets"]
        app.launch()
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30), app.debugDescription)
        let count = expectedCount(app)
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(home.wait(for: .runningForeground, timeout: 20), home.debugDescription)
        XCTAssertFalse(home.alerts.firstMatch.exists, home.debugDescription)
        capture("Home before editing", in: home)
        let frame = home.frame
        // Apple's documented path starts with holding empty Home background.
        // Use the actual right margin and reject an icon-covered point before
        // pressing; never long-press a guessed app icon or choose its menu.
        let point = CGPoint(x: frame.maxX - 20, y: frame.midY)
        XCTAssertTrue(frame.contains(point))
        let covered = home.icons.allElementsBoundByIndex.filter { $0.exists && $0.frame.contains(point) }
        XCTAssertTrue(covered.isEmpty, "Home background is occupied: \(covered.map(\.identifier))")
        XCTContext.runActivity(named: "Hold Home background at \(point)") { _ in
            home.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x - frame.minX, dy: point.y - frame.minY)).press(forDuration: 1.3)
        }
        tapChoice(["Edit", "編集"], in: home)
        capture("Home edit menu", in: home)
        tapChoice(["Add Widget", "Add Widgets", "ウィジェットを追加"], in: home)
        capture("Widget gallery", in: home)
        let search = home.searchFields
        guard let field = tapTestControl(search, in: home, keyboard: .keep) else { return }
        field.typeText("AnkiPad")
        let cells = home.cells.containing(.staticText, identifier: "AnkiPad")
        let buttons = home.buttons.matching(label(["AnkiPad"]))
        let knownResult = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (cells.count == 1 && cells.firstMatch.isHittable) || (buttons.count == 1 && buttons.firstMatch.isHittable)
        }, object: nil)
        guard XCTWaiter.wait(for: [knownResult], timeout: 30) == .completed else {
            capture("Widget search result unavailable", in: home)
            XCTFail("No unique foreground app row in the widget gallery: " + home.debugDescription); return
        }
        capture("Widget search results", in: home)
        if cells.count == 1 && cells.firstMatch.isHittable { tapTestControl(cells, in: home, keyboard: .keep) }
        else { tapTestControl(buttons, in: home, keyboard: .keep) }
        capture("Widget app gallery", in: home)
        // The first kind is the summary; its default small family follows the
        // currently selected profile. Do not change a page by guessed swipes.
        XCTAssertTrue(home.staticTexts["学習状況"].waitForExistence(timeout: 30), home.debugDescription)
        tapChoice(["Add Widget", "Add Widgets", "ウィジェットを追加"], in: home)
        tapChoice(["Done", "完了"], in: home)
        capture("Home after adding summary", in: home)
        let widgets = home.icons.matching(NSPredicate(format: "identifier == %@ AND value == %@", "AnkiPad", "Widget"))
        guard let widget = waitForTestControl(widgets, in: home, keyboard: .keep) else { return }
        let live = widget.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label == %@", "widget-summary-remaining", "残り\(count)枚"))
        guard let remaining = waitForTestControl(live, in: home, keyboard: .keep, timeout: 30, purpose: .observation) else { return }
        XCTAssertEqual(remaining.label, "残り\(count)枚", "Must read the app's current group snapshot, not a gallery sample or redaction")
        capture("Summary on Home", in: home)
        tapTestControl(widgets, in: home, keyboard: .keep)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), home.debugDescription)
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
