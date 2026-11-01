import XCTest

/// Application crash diagnosis, not an additional AnkiDroid feature claim.
final class ToolbarFocusReproductionTests: StudyFlowTestSupport {
    func testProductionToolbarInMinimalPresentedNavigationCanReturnAfterToggle() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-toolbar-focus-minimal"]
        app.launch()
        tapTestControl(app.buttons.matching(identifier: "focus-repro-settings"), in: app)
        let backTitle = NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern(["設定", "戻る", "Back"]))
        var previous = false
        for cycle in 1...3 {
            tapTestControl(app.buttons.matching(identifier: "focus-repro-toolbar"), in: app)
            let toggle = app.switches.matching(identifier: "toolbar-enabled")
            guard let row = waitForTestControl(toggle, in: app, purpose: .observation) else { return }
            XCTAssertEqual(row.value as? String, previous ? "1" : "0", "Real configuration binding survives navigation")
            let enabled = !previous
            guard setTestSwitch(toggle, enabled: enabled, in: app) else { return }
            XCTContext.runActivity(named: "Minimal toolbar before native back cycle \(cycle)") { activity in
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "Minimal toolbar before back"; hierarchy.lifetime = .keepAlways
                let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screen.lifetime = .keepAlways
                activity.add(hierarchy); activity.add(screen)
            }
            tapTestControl(app.navigationBars["操作バーの設定"].buttons.matching(backTitle), in: app)
            requireTestCondition("Minimal toolbar native back returns on cycle \(cycle)", in: app) {
                app.state == .runningForeground && !app.navigationBars["操作バーの設定"].exists
                    && app.navigationBars["設定"].exists && app.collectionViews["focus-repro-form"].exists
            }
            previous = enabled
        }
        tapTestControl(app.buttons.matching(identifier: "focus-repro-cancel"), in: app)
        waitForTestControl(app.buttons.matching(identifier: "focus-repro-settings"), in: app)
        XCTAssertFalse(app.alerts.element.exists)
    }

    func testActualSettingsParentCanReturnFromProductionToolbar() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-toolbar-focus-parent", "--uitest-fixture"]
        app.launch()
        tapTestControl(app.buttons.matching(identifier: "focus-parent-settings"), in: app)
        let link = app.buttons.matching(identifier: "toolbar-settings-open")
        revealSettingsControl(link.element, in: app)
        tapTestControl(link, in: app)
        guard setTestSwitch(app.switches.matching(identifier: "toolbar-enabled"), enabled: true, in: app) else { return }
        XCTContext.runActivity(named: "Actual parent toolbar before native back") { activity in
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Actual parent before back"; hierarchy.lifetime = .keepAlways
            let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screen.lifetime = .keepAlways
            activity.add(hierarchy); activity.add(screen)
        }
        let back = app.navigationBars["操作バーの設定"].buttons.matching(NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern(["設定", "戻る", "Back"])))
        tapTestControl(back, in: app)
        requireTestCondition("Actual parent retains its foreground form after native back", in: app) {
            app.state == .runningForeground && !app.navigationBars["操作バーの設定"].exists
                && app.navigationBars["設定"].exists && app.collectionViews["settings-form"].exists
        }
        tapTestControl(app.buttons.matching(identifier: "settings-cancel"), in: app)
        waitForTestControl(app.buttons.matching(identifier: "focus-parent-settings"), in: app)
        // Check the real non-diagnostic entry using the same persisted fixture.
        app.terminate(); app.launchArguments = []; app.launch()
        waitForTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        waitForTestControl(app.buttons.matching(identifier: "deck-1"), in: app, purpose: .observation)
        XCTAssertFalse(app.alerts.element.exists)
    }

    func testScrollableMinimalParentCanReturnFromProductionToolbar() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-toolbar-focus-scroll"]
        app.launch()
        tapTestControl(app.buttons.matching(identifier: "focus-scroll-settings"), in: app)
        let form = app.collectionViews["focus-scroll-form"]
        tapTestControl(app.buttons.matching(identifier: "focus-scroll-toolbar"), in: app, form: form)
        guard setTestSwitch(app.switches.matching(identifier: "toolbar-enabled"), enabled: true, in: app) else { return }
        XCTContext.runActivity(named: "Scrollable parent before native back") { activity in
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Scrollable parent before back"; hierarchy.lifetime = .keepAlways
            let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screen.lifetime = .keepAlways
            activity.add(hierarchy); activity.add(screen)
        }
        tapTestControl(app.navigationBars["操作バーの設定"].buttons.matching(NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern(["設定", "戻る", "Back"]))), in: app)
        requireTestCondition("Scrollable minimal parent survives native back", in: app) {
            app.state == .runningForeground && !app.navigationBars["操作バーの設定"].exists
                && app.navigationBars["設定"].exists && app.collectionViews["focus-scroll-form"].exists
        }
        tapTestControl(app.buttons.matching(identifier: "focus-scroll-cancel"), in: app)
        waitForTestControl(app.buttons.matching(identifier: "focus-scroll-settings"), in: app)
        XCTAssertFalse(app.alerts.element.exists)
    }

    func testLocallyOwnedScrollableParentCanReturnFromProductionToolbar() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-toolbar-focus-owner"]
        app.launch()
        tapTestControl(app.buttons.matching(identifier: "focus-owner-settings"), in: app)
        let form = app.collectionViews["focus-owner-form"]
        tapTestControl(app.buttons.matching(identifier: "focus-owner-toolbar"), in: app, form: form)
        guard setTestSwitch(app.switches.matching(identifier: "toolbar-enabled"), enabled: true, in: app) else { return }
        XCTContext.runActivity(named: "Locally owned parent before native back") { activity in
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Locally owned parent before back"; hierarchy.lifetime = .keepAlways
            let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screen.lifetime = .keepAlways
            activity.add(hierarchy); activity.add(screen)
        }
        tapTestControl(app.navigationBars["操作バーの設定"].buttons.matching(NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern(["設定", "戻る", "Back"]))), in: app)
        requireTestCondition("Locally owned parent survives native back", in: app) {
            app.state == .runningForeground && !app.navigationBars["操作バーの設定"].exists
                && app.navigationBars["設定"].exists && app.collectionViews["focus-owner-form"].exists
        }
        tapTestControl(app.buttons.matching(identifier: "focus-owner-cancel"), in: app)
        waitForTestControl(app.buttons.matching(identifier: "focus-owner-settings"), in: app)
        XCTAssertFalse(app.alerts.element.exists)
    }
}
