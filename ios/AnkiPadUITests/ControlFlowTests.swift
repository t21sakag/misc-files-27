import XCTest

final class ControlFlowTests: StudyFlowTestSupport {
    func testDeckContextDeletionKeepsTargetAfterConfirmationDismisses() {
        let app = makeApplication()
        app.launch()
        tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        tapTestMenuAction(titles: ["デッキを作成"], in: app)
        let dialog = app.alerts.matching(identifier: "デッキを作成")
        typeInEmptyTestField(dialog.textFields, text: "Deletion confirmation check", in: app)
        tapTestAlertAction(titles: ["保存"], in: dialog, application: app)
        let names = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'deck-' AND label CONTAINS 'Deletion confirmation check'"))
        guard let created = waitForTestControl(names, in: app) else { return }
        let id = created.identifier
        let target = app.buttons.matching(identifier: id)
        created.press(forDuration: 1)
        tapTestMenuAction(titles: ["削除"], in: app)
        tapTestAlertAction("deck-delete-confirm", in: app.popovers.sheets, application: app)
        requireTestCondition("Confirmed deck target is removed", in: app) { target.count == 0 }
        waitForTestControl(app.buttons.matching(identifier: "deck-1"), in: app, purpose: .observation)
        app.terminate(); app.launchArguments = []; app.launch()
        waitForTestControl(app.buttons.matching(identifier: "deck-1"), in: app)
        XCTAssertEqual(target.count, 0, "Deletion must persist across relaunch")
        XCTAssertEqual(names.count, 0, "Deleted deck name must not reappear with a different ID")
        XCTAssertFalse(app.alerts.element.exists)
    }

    func testCustomToolbarAndTouchAssignmentPersistAndPerformNativeActions() {
        let app = makeApplication()
        app.launch()
        tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        tapTestMenuAction(titles: ["設定"], in: app)
        let toolbarLink = app.buttons.matching(identifier: "toolbar-settings-open")
        revealSettingsControl(toolbarLink.element, in: app)
        tapTestControl(toolbarLink, in: app)
        guard setTestSwitch(app.switches.matching(identifier: "toolbar-enabled"), enabled: true, in: app) else { return }
        // Preserve the real back-navigation path implicated by the earlier
        // app focus assertion. Do not replace it with dismiss/relaunch.
        XCTContext.runActivity(named: "Before toolbar settings back navigation") { activity in
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Toolbar settings before navigation"; hierarchy.lifetime = .keepAlways
            let screen = XCTAttachment(screenshot: app.screenshot()); screen.lifetime = .keepAlways
            activity.add(hierarchy); activity.add(screen)
        }
        let backTitle = NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern(["設定", "戻る", "Back"]))
        tapTestControl(app.navigationBars["操作バーの設定"].buttons.matching(backTitle), in: app)
        requireTestCondition("Native back navigation returns to settings", in: app) {
            app.state == .runningForeground && !app.navigationBars["操作バーの設定"].exists && app.navigationBars["設定"].exists
        }
        let touchLink = app.buttons.matching(identifier: "touch-settings-open")
        revealSettingsControl(touchLink.element, in: app)
        tapTestControl(touchLink, in: app)
        let form = app.collectionViews["touch-settings-form"]
        guard waitForTestControl(app.switches.matching(identifier: "touch-enabled"), in: app, form: form, purpose: .observation) != nil,
              setTestSwitch(app.switches.matching(identifier: "touch-enabled"), enabled: true, in: app) else { return }
        tapTestControl(app.buttons.matching(identifier: "touch-zone-8"), in: app, form: form)
        tapTestMenuAction(titles: ["解答を表示"], in: app)
        tapTestControl(app.navigationBars["タッチ領域の割り当て"].buttons.matching(backTitle), in: app)
        waitForTestControl(app.navigationBars.matching(identifier: "設定"), in: app, purpose: .observation)
        tapTestControl(app.buttons.matching(identifier: "settings-save"), in: app)
        waitForTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        app.terminate(); app.launchArguments = []; app.launch()
        tapTestControl(app.buttons.matching(identifier: "deck-1"), in: app)
        waitForTestControl(app.webViews.staticTexts.matching(identifier: "AnkiDroid API metadata verified"), in: app, purpose: .observation)
        // These unique action IDs exist only in the enabled persisted toolbar;
        // exercise them rather than relying on an inferred container AX type.
        func actions(_ title: String) -> XCUIElementQuery {
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'review-toolbar-' AND label == %@", title))
        }
        tapTestControl(actions("マークを切り替え"), in: app)
        tapTestControl(app.buttons.matching(identifier: "reviewer-menu"), in: app)
        tapTestMenuAction(titles: ["マークを外す"], in: app)
        tapTestControl(actions("ノートを編集"), in: app)
        tapTestControl(app.buttons.matching(identifier: "note-close"), in: app)
        waitForTestControl(app.buttons.matching(identifier: "reveal"), in: app)
        // Blank card space in configured lower-right zone, not a DOM control.
        // Use the shared app-anchored frame mapping to avoid WebKit offsets.
        guard let web = waitForTestCardWebView(in: app) else { return }
        tapScreenFrame(web, in: app, normalizedOffset: CGVector(dx: 0.9, dy: 0.92))
        waitForTestControl(app.buttons.matching(identifier: "answer-2"), in: app)
        XCTAssertFalse(app.alerts.element.exists)
    }
}
