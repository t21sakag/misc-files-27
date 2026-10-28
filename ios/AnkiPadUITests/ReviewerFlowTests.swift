import XCTest

final class ReviewerFlowTests: StudyFlowTestSupport {
    func testReviewVoicePanelClosesWithoutChangingCard() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["AnkiDroid API metadata verified"].waitForExistence(timeout: 30), app.debugDescription)
        let options = web.buttons["API options"]
        XCTAssertTrue(options.waitForExistence(timeout: 30))
        options.tap()
        let voice = app.buttons["review-option-voice"]
        let list = app.collectionViews["reviewer-options-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 20), app.debugDescription)
        for _ in 0..<6 {
            if voice.exists && voice.isHittable { break }
            list.swipeUp()
        }
        XCTAssertTrue(voice.waitForExistence(timeout: 20), app.debugDescription)
        voice.tap()
        let panel = app.navigationBars["自分の声"]
        XCTAssertTrue(panel.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["録音を開始"].exists)
        XCTAssertFalse(app.buttons["録音を再生"].exists)
        panel.buttons["閉じる"].tap()
        XCTAssertTrue(options.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["reveal"].exists)
        XCTAssertTrue(web.staticTexts["AnkiDroid API metadata verified"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testAutoAdvancePausesWhileEditing() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()
        let reveal = app.buttons["reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 30))
        reveal.tap()
        XCTAssertTrue(app.buttons["answer-2"].waitForExistence(timeout: 20))
        let menu = app.buttons["reviewer-menu"]
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["auto-advance-toggle"].tap()
        if !app.buttons["review-edit-note"].exists { menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        app.buttons["review-edit-note"].tap()
        let close = app.buttons["note-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 20), app.debugDescription)
        Thread.sleep(forTimeInterval: 9)
        close.tap()
        XCTAssertTrue(app.buttons["answer-2"].waitForExistence(timeout: 20), "The answer changed while its note editor was open. " + app.debugDescription)
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["auto-advance-toggle"].tap()
    }

    func testCustomSchedulingChangesAnswerInterval() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.press(forDuration: 1)
        app.buttons["デッキオプション"].tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 30))
        let custom = web.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "カスタムスケジューリング")).firstMatch
        for _ in 0..<15 { if custom.exists && custom.isHittable { break }; web.swipeUp() }
        waitUntilHittable(custom)
        XCTAssertTrue(custom.exists, app.debugDescription)
        custom.tap()
        let code = web.textViews.firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 15), app.debugDescription)
        code.tap()
        code.typeText("states.easy.normal.review.scheduledDays = 7;")
        let save = web.buttons["保存"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 15), app.debugDescription)
        save.tap()
        XCTAssertTrue(deck.waitForExistence(timeout: 30), app.debugDescription)
        deck.tap()
        let reveal = app.buttons["reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 30), app.debugDescription)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: reveal)
        waitForExpectations(timeout: 30)
        reveal.tap()
        let easy = app.buttons["answer-3"]
        XCTAssertTrue(easy.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(easy.label.contains("7"), easy.label)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testFullscreenCanBeRestoredWithTripleTap() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let menu = app.buttons["collection-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["設定"].tap()
        let mode = app.buttons["review-display-mode"]
        revealSettingsControl(mode, in: app)
        mode.tap()
        app.buttons["カードのみ"].tap()
        app.buttons["settings-save"].tap()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["reveal"].exists)
        web.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        XCTAssertTrue(app.buttons["reveal"].waitForExistence(timeout: 20), app.debugDescription)
    }

    func testImportedDeckCanBeReviewedAndUndone() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertTrue(deck.isEnabled)
        deck.tap()
        let reveal = app.buttons["reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 20))
        app.buttons["whiteboard-toggle"].tap()
        let board = app.scrollViews["whiteboard"]
        XCTAssertTrue(board.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["whiteboard-toggle"].tap()
        reveal.tap()
        let good = app.buttons["answer-2"]
        XCTAssertTrue(good.waitForExistence(timeout: 20), app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "iPad-answer-screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        good.tap()
        let undo = app.buttons["review-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 20))
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: undo)
        waitForExpectations(timeout: 20)
        undo.tap()
        XCTAssertTrue(reveal.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.staticTexts["新規 1 · 学習 0 · 復習 0"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
    }

    func testWhiteboardUndoesStrokesAndKeepsPerDeckVisibility() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 60), app.debugDescription)
        deck.tap()
        let reveal = app.buttons["reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["whiteboard-toggle"].tap()
        let board = app.descendants(matching: .any).matching(identifier: "whiteboard").firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 20), app.debugDescription)
        func strokes() -> Int? {
            guard board.exists, let value = board.value as? String else { return nil }
            return value.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init).first
        }
        func waitForStrokes(_ count: Int) {
            let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in strokes() == count }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 20), .completed, app.debugDescription)
        }
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.4)).press(forDuration: 0.1,
            thenDragTo: board.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.45)))
        waitForStrokes(1)
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6)).press(forDuration: 0.1,
            thenDragTo: board.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.65)))
        waitForStrokes(2)
        let undo = app.buttons["review-undo"]
        undo.tap()
        waitForStrokes(1)
        undo.tap()
        waitForStrokes(0)
        XCTAssertTrue(reveal.exists, "Undoing strokes must not leave the question side")

        let menu = app.buttons["reviewer-menu"]
        menu.tap()
        let visibility = app.buttons["whiteboard-visibility"].firstMatch
        XCTAssertTrue(visibility.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(visibility.label, "手書きを隠す")
        visibility.tap()
        XCTAssertTrue(board.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(reveal.isHittable)

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(deck.waitForExistence(timeout: 60), app.debugDescription)
        deck.tap()
        XCTAssertTrue(reveal.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertFalse(board.exists, "Hidden whiteboard must stay hidden for this deck after relaunch")
        menu.tap()
        XCTAssertTrue(visibility.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(visibility.label, "手書きを表示", "The deck must remember that its whiteboard is enabled")
        visibility.tap()
        XCTAssertTrue(board.waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["whiteboard-toggle"].tap()
        XCTAssertTrue(board.waitForNonExistence(timeout: 10), app.debugDescription)
        menu.tap()
        XCTAssertFalse(app.buttons["whiteboard-visibility"].firstMatch.waitForExistence(timeout: 3), "Disabling removes the visibility option")
    }

    func testSwipeCanRevealAndAnswerThenUndo() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()
        let reveal = app.buttons["reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 30))
        let revealReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: reveal)
        XCTAssertEqual(XCTWaiter.wait(for: [revealReady], timeout: 30), .completed)
        let web = app.webViews.firstMatch
        web.swipeLeft()
        let good = app.buttons["answer-2"]
        XCTAssertTrue(good.waitForExistence(timeout: 20), app.debugDescription)
        let answerReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: good)
        XCTAssertEqual(XCTWaiter.wait(for: [answerReady], timeout: 20), .completed)
        web.swipeLeft()
        let answered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: good)
        XCTAssertEqual(XCTWaiter.wait(for: [answered], timeout: 30), .completed, app.debugDescription)
        let undo = app.buttons["review-undo"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: undo)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        undo.tap()
        XCTAssertTrue(reveal.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

}
