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
    private func launchWidgetApplication() -> XCUIApplication {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture", "--uitest-widgets"]
        app.launch()
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30), app.debugDescription)
        return app
    }
    private func addSummary(_ app: XCUIApplication) -> (XCUIApplication, Int)? {
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
        guard let field = tapTestControl(search, in: home, keyboard: .keep) else { return nil }
        field.typeText("AnkiPad")
        let cells = home.cells.containing(.staticText, identifier: "AnkiPad")
        let buttons = home.buttons.matching(label(["AnkiPad"]))
        let knownResult = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (cells.count == 1 && cells.firstMatch.isHittable) || (buttons.count == 1 && buttons.firstMatch.isHittable)
        }, object: nil)
        guard XCTWaiter.wait(for: [knownResult], timeout: 30) == .completed else {
            capture("Widget search result unavailable", in: home)
            XCTFail("No unique foreground app row in the widget gallery: " + home.debugDescription); return nil
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
        return (home, count)
    }
    func testHomeGalleryAddsSummaryWithActualSharedCountsAndOpensApp() {
        let app = launchWidgetApplication()
        guard let (home, count) = addSummary(app) else { return }
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
    private func selectFixedDefaultProfile(in home: XCUIApplication) -> Bool {
        let widgets = home.icons.matching(NSPredicate(format: "identifier == %@ AND value == %@", "AnkiPad", "Widget"))
        guard let widget = waitForTestControl(widgets, in: home, keyboard: .keep) else { return false }
        widget.press(forDuration: 1.3)
        capture("Summary context menu", in: home)
        tapChoice(["Edit Widget", "ウィジェットを編集"], in: home)
        capture("Summary configuration", in: home)
        // The observed OS row has a separate static parameter title and a
        // value-only Button. Never concatenate adjacent labels into a title.
        let parameter = home.buttons.matching(label(["現在のプロファイル", "Current profile"]))
        guard tapTestControl(parameter, in: home, keyboard: .keep) != nil else { return false }
        capture("Summary profile choices", in: home)
        let fixed = home.collectionViews.buttons.matching(label(["既定"]))
        guard tapTestControl(fixed, in: home, keyboard: .keep) != nil else { return false }
        capture("Summary fixed profile chosen", in: home)
        // Apple's configuration sheet commits by tapping empty Home background.
        // This is the same measured, icon-free margin used for Home editing.
        let frame = home.frame
        let point = CGPoint(x: frame.maxX - 20, y: frame.midY)
        XCTAssertTrue(frame.contains(point))
        XCTAssertTrue(home.icons.allElementsBoundByIndex.filter { $0.exists && $0.frame.contains(point) }.isEmpty)
        home.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x - frame.minX, dy: point.y - frame.minY)).tap()
        return true
    }
    func testSummaryConfigurationSelectsFixedProfileAndKeepsLiveCount() {
        let app = launchWidgetApplication()
        guard let (home, count) = addSummary(app) else { return }
        guard selectFixedDefaultProfile(in: home) else { return }
        let widgets = home.icons.matching(NSPredicate(format: "identifier == %@ AND value == %@", "AnkiPad", "Widget"))
        let live = widgets.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label == %@", "widget-summary-remaining", "残り\(count)枚"))
        guard waitForTestControl(live, in: home, keyboard: .keep, timeout: 30, purpose: .observation) != nil else { return }
        capture("Fixed profile summary on Home", in: home)
        guard let configured = waitForTestControl(widgets, in: home, keyboard: .keep) else { return }
        configured.press(forDuration: 1.3)
        tapChoice(["Edit Widget", "ウィジェットを編集"], in: home)
        capture("Summary configuration reopened", in: home)
        let saved = home.buttons.matching(label(["既定"]))
        _ = waitForTestControl(saved, in: home, keyboard: .keep, purpose: .observation)
    }

    private func waitForStoredProfile(_ app: XCUIApplication, isDefault: Bool, total: Int) {
        let states = app.staticTexts.matching(identifier: "widget-snapshot-state")
        guard let state = waitForTestControl(states, in: app, keyboard: .keep, purpose: .observation) else { return }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let raw = state.value as? String, let data = raw.data(using: .utf8),
                  let snapshot = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let selected = snapshot["selectedProfileID"] as? String,
                  (selected == "default") == isDefault,
                  let profiles = snapshot["profiles"] as? [[String: Any]],
                  let profile = profiles.first(where: { $0["id"] as? String == selected }),
                  let collection = profile["collection"] as? [String: Any],
                  let counts = collection["counts"] as? [String: Int] else { return false }
            return (counts["new"] ?? 0) + (counts["learning"] ?? 0) + (counts["review"] ?? 0) == total
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, app.debugDescription)
    }
    func testFixedSummarySurvivesActiveProfileSwitchAndOpensItsOwnProfile() {
        let app = launchWidgetApplication()
        guard let (home, count) = addSummary(app) else { return }
        guard selectFixedDefaultProfile(in: home) else { return }
        app.activate()
        guard tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app) != nil else { return }
        guard tapTestControl(app.buttons.matching(identifier: "profiles-open"), in: app) != nil else { return }
        guard tapTestControl(app.buttons.matching(identifier: "profile-add"), in: app) != nil else { return }
        let creation = app.alerts.matching(NSPredicate(format: "label == %@", "プロファイルを追加"))
        // Observed SwiftUI alert TextField exports its placeholder, not the
        // source accessibility ID. The foreground creation alert has one field.
        guard let name = tapTestControl(creation.textFields, in: app, keyboard: .keep) else { return }
        name.typeText("Widget secondary")
        guard tapTestAlertAction("profile-save", in: creation, application: app) != nil else { return }
        waitForStoredProfile(app, isDefault: false, total: 0)
        capture("Secondary profile selected and published", in: app)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(home.wait(for: .runningForeground, timeout: 20))
        let widgets = home.icons.matching(NSPredicate(format: "identifier == %@ AND value == %@", "AnkiPad", "Widget"))
        let live = widgets.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label == %@", "widget-summary-remaining", "残り\(count)枚"))
        guard waitForTestControl(live, in: home, keyboard: .keep, timeout: 30, purpose: .observation) != nil else { return }
        capture("Fixed summary retains original profile count", in: home)
        guard tapTestControl(widgets, in: home, keyboard: .keep) != nil else { return }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        waitForStoredProfile(app, isDefault: true, total: count)
        capture("Widget opened its fixed profile", in: app)
    }

}
