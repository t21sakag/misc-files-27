import XCTest

final class ControlFlowTests: StudyFlowTestSupport {
    func testDeckContextDeletionKeepsTargetAfterConfirmationDismisses() {
        let app = makeApplication()
        app.launch()
        let menu = app.buttons["collection-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30)); menu.tap(); app.buttons["デッキを作成"].tap()
        let dialog = app.alerts["デッキを作成"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 20))
        let field = dialog.textFields.firstMatch
        field.tap(); field.typeText("Deletion confirmation check")
        dialog.buttons["保存"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'deck-' AND label CONTAINS 'Deletion confirmation check'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), app.debugDescription)
        row.press(forDuration: 1)
        app.buttons["削除"].firstMatch.tap()
        let confirm = app.buttons["deck-delete-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 20), app.debugDescription)
        confirm.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.buttons["deck-1"].exists, "Unrelated fixture deck must remain")
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30))
        XCTAssertFalse(row.exists, "Deletion must persist across relaunch")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testCustomToolbarAndTouchAssignmentPersistAndPerformNativeActions() {
        let app = makeApplication()
        app.launch()
        let menu = app.buttons["collection-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.tap(); app.buttons["設定"].tap()
        let settings = app.collectionViews["settings-form"]
        let toolbarLink = app.buttons["toolbar-settings-open"]
        for _ in 0..<12 { if toolbarLink.exists && toolbarLink.isHittable { break }; settings.swipeUp() }
        waitUntilHittable(toolbarLink); toolbarLink.tap()
        func enable(_ id: String) {
            let outer = app.switches[id]
            XCTAssertTrue(outer.waitForExistence(timeout: 20))
            let control = outer.switches.firstMatch.exists ? outer.switches.firstMatch : outer
            if control.value as? String != "1" { control.tap() }
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: control)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        }
        enable("toolbar-enabled")
        app.navigationBars["操作バーの設定"].buttons.element(boundBy: 0).tap()
        let touchLink = app.buttons["touch-settings-open"]
        XCTAssertTrue(touchLink.waitForExistence(timeout: 20)); touchLink.tap()
        enable("touch-enabled")
        let zone = app.buttons["touch-zone-8"]
        for _ in 0..<12 { if zone.exists && zone.isHittable { break }; app.collectionViews["touch-settings-form"].swipeUp() }
        waitUntilHittable(zone); zone.tap()
        let show = app.buttons["解答を表示"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 20)); show.tap()
        app.navigationBars["タッチ領域の割り当て"].buttons.element(boundBy: 0).tap()
        app.buttons["settings-save"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        app.terminate(); app.launchArguments = []; app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["AnkiDroid API metadata verified"].waitForExistence(timeout: 30))
        let toolbar = app.descendants(matching: .any).matching(identifier: "custom-review-toolbar").firstMatch
        XCTAssertTrue(toolbar.waitForExistence(timeout: 20), "Enabled toolbar must survive relaunch")
        func action(_ title: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'review-toolbar-' AND label == %@", title)).firstMatch
        }
        let mark = action("マークを切り替え")
        waitUntilHittable(mark); mark.tap()
        app.buttons["reviewer-menu"].tap()
        let remove = app.buttons["マークを外す"]
        XCTAssertTrue(remove.waitForExistence(timeout: 20), "Toolbar must perform the actual native mark operation")
        remove.tap()
        let edit = action("ノートを編集")
        waitUntilHittable(edit); edit.tap()
        let close = app.buttons["note-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 20)); close.tap()
        XCTAssertTrue(app.buttons["reveal"].waitForExistence(timeout: 20))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["reveal"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
        // Blank card space in configured lower-right zone, not a DOM control.
        web.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.92)).tap()
        XCTAssertTrue(app.buttons["answer-2"].waitForExistence(timeout: 20), "Persisted region assignment must reveal through the actual WebKit tap bridge")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
