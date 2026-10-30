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
        guard let state = waitForTestControl(app.staticTexts.matching(identifier: "widget-snapshot-state"), in: app, keyboard: .keep, purpose: .observation) else { return 0 }
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
    private func addWidget(_ app: XCUIApplication, page: Int = 1, title: String = "学習状況") -> (XCUIApplication, Int)? {
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
        // Recorded gallery has one nine-page indicator, distinct from the
        // Home screen's Page control. Observe every transition before acting.
        XCTAssertTrue((1...9).contains(page))
        let carousel = home.scrollViews.containing(.pageIndicator, identifier: nil)
        if page > 1 {
            for current in 1..<page {
                let indicator = home.pageIndicators.matching(NSPredicate(format: "value == %@", "page \(current) of 9"))
                guard waitForTestControl(indicator, in: home, keyboard: .keep, purpose: .observation) != nil,
                      let content = waitForTestControl(carousel, in: home, keyboard: .keep) else { return nil }
                content.swipeLeft(velocity: .slow)
                let advanced = home.pageIndicators.matching(NSPredicate(format: "value == %@", "page \(current + 1) of 9"))
                guard waitForTestControl(advanced, in: home, keyboard: .keep, purpose: .observation) != nil else { return nil }
            }
        }
        let kind = home.buttons.matching(label(["AnkiPad, " + title]))
        guard waitForTestControl(kind, in: home, keyboard: .keep, purpose: .observation) != nil else { return nil }
        capture("Selected widget kind " + title, in: home)
        tapChoice(["Add Widget", "Add Widgets", "ウィジェットを追加"], in: home)
        tapChoice(["Done", "完了"], in: home)
        capture("Home after adding summary", in: home)
        return (home, count)
    }
    func testHomeGalleryAddsSummaryWithActualSharedCountsAndOpensApp() {
        let app = launchWidgetApplication()
        guard let (home, count) = addWidget(app) else { return }
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
        guard let (home, count) = addWidget(app) else { return }
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
        guard let (home, count) = addWidget(app) else { return }
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

    func testAddNoteWidgetOpensEmptyDraftAndCancelKeepsDueCount() {
        let app = launchWidgetApplication()
        // Bundle order/families: summary2, deck list3, analysis2, add-note2.
        guard let (home, count) = addWidget(app, page: 8, title: "ノートを追加") else { return }
        let widgets = home.icons.matching(NSPredicate(format: "identifier == %@ AND value == %@", "AnkiPad", "Widget"))
        let caption = widgets.staticTexts.matching(label(["ノートを追加"]))
        guard waitForTestControl(caption, in: home, keyboard: .keep, timeout: 30, purpose: .observation) != nil else { return }
        capture("Add note widget on Home", in: home)
        guard tapTestControl(widgets, in: home, keyboard: .keep) != nil else { return }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        let fields = app.textViews.matching(identifier: "note-field-0")
        guard let front = waitForTestControl(fields, in: app, keyboard: .keep, purpose: .observation) else { return }
        XCTAssertEqual(front.value as? String, "")
        capture("Widget opened unsaved editor", in: app)
        guard tapTestControl(app.buttons.matching(identifier: "note-close"), in: app) != nil else { return }
        waitForStoredProfile(app, isDefault: true, total: count)
        XCTAssertFalse(app.textViews["note-field-0"].exists)
    }

    func testAnalysisWidgetShowsStoredDeckCountsAndOpensReview() {
        let app = launchWidgetApplication()
        _ = expectedCount(app)
        guard let state = waitForTestControl(app.staticTexts.matching(identifier: "widget-snapshot-state"), in: app, keyboard: .keep, purpose: .observation),
              let raw = state.value as? String, let data = raw.data(using: .utf8),
              let snapshot = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let profiles = snapshot["profiles"] as? [[String: Any]],
              let profile = profiles.first(where: { $0["id"] as? String == "default" }),
              let collection = profile["collection"] as? [String: Any],
              let decks = collection["decks"] as? [[String: Any]],
              let deck = decks.first(where: { $0["id"] as? String == "1" }),
              let counts = deck["counts"] as? [String: Int] else {
            XCTFail("Missing actual stored deck snapshot"); return
        }
        XCTAssertGreaterThan(counts["new"] ?? 0, 0)
        guard let (home, _) = addWidget(app, page: 6, title: "デッキの枚数") else { return }
        let widgets = home.icons.matching(NSPredicate(format: "identifier == %@ AND value == %@", "AnkiPad", "Widget"))
        // These app-owned accessible groups expose a category label and its
        // actual numeric value. Their role is intentionally opaque to the OS;
        // resolve by owned identity/value inside this one widget, not by text.
        for (key, title) in [("new", "新規"), ("learning", "学習"), ("review", "復習")] {
            guard let count = counts[key] else { XCTFail("Missing count " + key); return }
            let value = widgets.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label == %@ AND value == %@",
                "widget-count-" + key, title, String(count)))
            guard waitForTestControl(value, in: home, keyboard: .keep, timeout: 30, purpose: .observation) != nil else { return }
        }
        capture("Deck analysis counts on Home", in: home)
        guard tapTestControl(widgets, in: home, keyboard: .keep) != nil else { return }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        guard waitForTestControl(app.buttons.matching(identifier: "reveal"), in: app, keyboard: .keep) != nil else { return }
        capture("Analysis widget opened review", in: app)
    }

    func testDeckListWidgetSelectsDeckAndOpensItsReview() {
        let app = launchWidgetApplication()
        _ = expectedCount(app)
        guard let state = waitForTestControl(app.staticTexts.matching(identifier: "widget-snapshot-state"), in: app, keyboard: .keep, purpose: .observation),
              let raw = state.value as? String, let data = raw.data(using: .utf8),
              let snapshot = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let profiles = snapshot["profiles"] as? [[String: Any]],
              let profile = profiles.first(where: { $0["id"] as? String == "default" }),
              let collection = profile["collection"] as? [String: Any],
              let decks = collection["decks"] as? [[String: Any]],
              let deck = decks.first(where: { $0["id"] as? String == "1" }),
              let name = deck["name"] as? String, let profileName = profile["name"] as? String,
              let counts = deck["counts"] as? [String: Int],
              let new = counts["new"], let learning = counts["learning"], let review = counts["review"] else {
            XCTFail("Missing stored deck values"); return
        }
        guard let (home, _) = addWidget(app, page: 3, title: "デッキ一覧") else { return }
        let widgets = home.icons.matching(NSPredicate(format: "identifier == %@ AND value == %@", "AnkiPad", "Widget"))
        let empty = widgets.staticTexts.matching(label(["ウィジェットを編集してデッキを選択してください。"]))
        guard waitForTestControl(empty, in: home, keyboard: .keep, timeout: 30, purpose: .observation) != nil,
              let widget = waitForTestControl(widgets, in: home, keyboard: .keep) else { return }
        widget.press(forDuration: 1.3)
        tapChoice(["Edit Widget", "ウィジェットを編集"], in: home)
        capture("Deck list configuration", in: home)
        // This intent has one parameter. Wait for exactly one foreground
        // actionable value Button rather than guessing its empty-value title.
        let parameter = home.buttons
        guard tapTestControl(parameter, in: home, keyboard: .keep) != nil else { return }
        capture("Deck list available choices", in: home)
        tapChoice([profileName + " · " + name], in: home)
        capture("Deck list selected choice", in: home)
        tapChoice(["Done", "完了"], in: home)
        capture("Deck list configuration after choice", in: home)
        let frame = home.frame, point = CGPoint(x: home.frame.maxX - 20, y: home.frame.midY)
        XCTAssertTrue(frame.contains(point))
        XCTAssertTrue(home.icons.allElementsBoundByIndex.filter { $0.exists && $0.frame.contains(point) }.isEmpty)
        home.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x - frame.minX, dy: point.y - frame.minY)).tap()
        let leaf = name.components(separatedBy: "::").last ?? name
        let row = widgets.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label == %@ AND value == %@",
            "widget-deck-default:1", leaf, "新規 \(new), 学習 \(learning), 復習 \(review)"))
        guard waitForTestControl(row, in: home, keyboard: .keep, timeout: 30, purpose: .observation) != nil else { return }
        capture("Configured deck list on Home", in: home)
        guard tapTestControl(row, in: home, keyboard: .keep) != nil else { return }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        guard waitForTestControl(app.buttons.matching(identifier: "reveal"), in: app, keyboard: .keep) != nil else { return }
        capture("Deck row opened review", in: app)
    }

}
