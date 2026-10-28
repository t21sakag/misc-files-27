import XCTest

final class CardAPIFlowTests: StudyFlowTestSupport {
    func testAnkiDroidCardJavaScriptReadsNativeMetadata() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()
        XCTAssertTrue(app.webViews.staticTexts["AnkiDroid API metadata verified"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.webViews.staticTexts["MathJax typeset verified"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.webViews.staticTexts["Stored LaTeX image verified"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.webViews.staticTexts["Embedded frame loaded; native bridge denied"].waitForExistence(timeout: 30), app.debugDescription)
        app.webViews.buttons["API mutations"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.webViews.staticTexts["AnkiDroid API mutations verified"].waitForExistence(timeout: 30), app.debugDescription)
        let menu = app.buttons["reviewer-menu"]
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let actionsMenu = app.buttons["template-actions-menu"]
        XCTAssertTrue(actionsMenu.waitForExistence(timeout: 20), app.debugDescription)
        actionsMenu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["template-action-9"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["template-action-9"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Template action 9 verified"].waitForExistence(timeout: 20), app.debugDescription)
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["template-hint-next"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Template hint revealed"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testJavaScriptDialogsReturnNativeInputAndDecisions() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()
        let button = app.webViews.buttons["API dialogs"]
        XCTAssertTrue(button.waitForExistence(timeout: 30))
        waitUntilHittable(button)
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let input = app.alerts.textFields["card-js-prompt-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 20), app.debugDescription)
        input.tap(); input.typeText("template input")
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.alerts.staticTexts["Template confirm"].waitForExistence(timeout: 20), app.debugDescription)
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.alerts.staticTexts["Template alert"].waitForExistence(timeout: 20), app.debugDescription)
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Template dialogs verified"].waitForExistence(timeout: 20), app.debugDescription)
        waitUntilHittable(button)
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(input.waitForExistence(timeout: 20), app.debugDescription)
        app.alerts.buttons["キャンセル"].tap()
        XCTAssertTrue(app.alerts.staticTexts["Template cancel confirm"].waitForExistence(timeout: 20), app.debugDescription)
        app.alerts.buttons["キャンセル"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Template dialog cancellation verified"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testNavigationAndReviewerOptionsAPIOpenNativePanels() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["AnkiDroid API metadata verified"].waitForExistence(timeout: 30), app.debugDescription)
        web.buttons["API options"].tap()
        let info = app.buttons["review-option-info"]
        XCTAssertTrue(info.waitForExistence(timeout: 20), app.debugDescription)
        info.tap()
        let bar = app.navigationBars["カード情報"]
        XCTAssertTrue(bar.waitForExistence(timeout: 30), app.debugDescription)
        let close = bar.buttons["閉じる"]
        waitUntilHittable(close)
        close.tap()
        XCTAssertTrue(bar.waitForNonExistence(timeout: 30), "Card information must dismiss before using the underlying card")
        XCTAssertTrue(web.buttons["API navigation"].waitForExistence(timeout: 20))
        waitUntilHittable(web.buttons["API navigation"])
        web.buttons["API navigation"].tap()
        let decks = app.buttons["destination-decks"]
        XCTAssertTrue(decks.waitForExistence(timeout: 20), app.debugDescription)
        decks.tap()
        XCTAssertTrue(deck.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testUnsafeCollectionAPIRequiresExplicitSetting() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["AnkiDroid API metadata verified"].waitForExistence(timeout: 30), app.debugDescription)
        web.buttons["API collection query"].tap()
        XCTAssertTrue(web.staticTexts["Collection access denied"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["デッキ"].tap()
        setCollectionPermission(app, enabled: true)
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()
        XCTAssertTrue(web.staticTexts["AnkiDroid API metadata verified"].waitForExistence(timeout: 30))
        web.buttons["API collection query"].tap()
        XCTAssertTrue(web.staticTexts["Collection query verified"].waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["デッキ"].tap()
        setCollectionPermission(app, enabled: false)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testPreviewCardAPIReadsAndRestoresFlag() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let menu = app.buttons["collection-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        setCollectionPermission(app, enabled: false)
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["browser-open"].tap()
        let search = app.searchFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", "検索（")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap(); search.typeText("Rust")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-card-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.press(forDuration: 1)
        app.buttons["プレビュー"].tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["AnkiDroid API metadata verified"].waitForExistence(timeout: 30), app.debugDescription)
        let probe = web.buttons["Preview API check"]
        XCTAssertTrue(probe.waitForExistence(timeout: 30), app.debugDescription)
        probe.tap()
        XCTAssertTrue(web.staticTexts["Preview API verified"].waitForExistence(timeout: 20), app.debugDescription)
        web.buttons["API mutations"].tap()
        XCTAssertTrue(web.staticTexts["AnkiDroid API mutations verified"].waitForExistence(timeout: 20), app.debugDescription)
        web.buttons["API collection query"].tap()
        XCTAssertTrue(web.staticTexts["Collection access denied"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["preview-close"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testPreviewNativeToastAndTagDialogPersistToPreviewedNote() {
        let app = makeApplication()
        app.launch()
        let menu = app.buttons["collection-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30)); menu.tap(); app.buttons["browser-open"].tap()
        let search = app.searchFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", "検索（")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20)); search.tap(); search.typeText("Rust")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'browser-card-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30)); row.press(forDuration: 1); app.buttons["プレビュー"].tap()
        let web = app.webViews.firstMatch
        let toast = web.buttons["Preview native toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 30)); toast.tap()
        let shown = app.staticTexts["preview-script-toast"]
        XCTAssertTrue(shown.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(shown.label, "プレビューの通知を確認")
        shown.tap()
        XCTAssertTrue(shown.waitForNonExistence(timeout: 10))
        let tags = web.buttons["Preview native tags"]
        XCTAssertTrue(tags.waitForExistence(timeout: 20)); tags.tap()
        let field = app.textFields["card-action-tags"]
        XCTAssertTrue(field.waitForExistence(timeout: 20), app.debugDescription)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        field.tap(); field.typeText(" preview-native-tag")
        app.buttons["card-action-apply"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 30))
        XCTAssertTrue(tags.waitForExistence(timeout: 30)); tags.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "preview-native-tag"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 20), .completed, app.debugDescription)
        app.navigationBars["タグを編集"].buttons["キャンセル"].tap()
        app.buttons["preview-close"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        assertBrowserContains(app, text: "tag:preview-native-tag", exists: true)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testPreviewFlagPersistsAfterClosing() {
        let app = makeApplication()
        app.launch()
        let menu = app.buttons["collection-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["browser-open"].tap()
        let search = app.searchFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", "検索（")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap(); search.typeText("Rust")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-card-")).firstMatch
        func openPreview() {
            XCTAssertTrue(row.waitForExistence(timeout: 30), app.debugDescription)
            row.press(forDuration: 1)
            app.buttons["プレビュー"].tap()
            let flags = app.buttons["preview-flags"]
            XCTAssertTrue(flags.waitForExistence(timeout: 30), app.debugDescription)
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: flags)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        }
        openPreview()
        let mark = app.buttons["preview-mark"]
        let originalMarkLabel = mark.label
        let toggledMarkLabel = originalMarkLabel == "マークを外す" ? "マークを付ける" : "マークを外す"
        mark.tap()
        let markChanged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", toggledMarkLabel), object: mark)
        XCTAssertEqual(XCTWaiter.wait(for: [markChanged], timeout: 20), .completed)
        let flags = app.buttons["preview-flags"]
        flags.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["preview-flag-4"].tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "フラグ 4"), object: flags)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 20), .completed)
        app.buttons["preview-close"].tap()
        openPreview()
        XCTAssertEqual(flags.label, "フラグ 4", app.debugDescription)
        XCTAssertEqual(mark.label, toggledMarkLabel, app.debugDescription)
        mark.tap()
        let markRestored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", originalMarkLabel), object: mark)
        XCTAssertEqual(XCTWaiter.wait(for: [markRestored], timeout: 20), .completed)
        flags.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["preview-flag-0"].tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "フラグなし"), object: flags)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 20), .completed)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

}
