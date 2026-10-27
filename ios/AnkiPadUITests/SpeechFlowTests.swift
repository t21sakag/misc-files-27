import XCTest
import AVFoundation

final class SpeechFlowTests: StudyFlowTestSupport {
    @MainActor
    func testNativeSpeechSynthesisQueueCompletes() async {
        let audio = CardAudio()
        defer { audio.stop() }
        let complete = expectation(description: "Actual installed speech engine finishes its queue")
        let start = Date()
        audio.play([["tts": ["fieldText": "Native speech playback check.", "lang": "en-US", "voices": [], "speed": 1.0]]], media: FileManager.default.temporaryDirectory) { complete.fulfill() }
        await fulfillment(of: [complete], timeout: 20)
        XCTAssertGreaterThan(Date().timeIntervalSince(start), 0.1)
        XCTAssertFalse(audio.isPlaying)
    }
    private func tapReady(_ item: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true AND hittable == true"), object: item)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
        item.tap()
    }
    private func enableTTS(_ app: XCUIApplication) {
        let menu = app.buttons["collection-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30)); menu.tap(); app.buttons["設定"].tap()
        let form = app.collectionViews["settings-form"]
        let outer = app.switches["tts-enabled"]
        for _ in 0..<12 { if outer.exists && outer.isHittable { break }; form.swipeUp() }
        XCTAssertTrue(outer.waitForExistence(timeout: 20))
        let inner = outer.switches.firstMatch
        let item = inner.exists ? inner : outer
        if item.value as? String != "1" {
            if inner.exists { inner.tap() } else { outer.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
        }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: item)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        app.buttons["settings-save"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
    }
    private func openChoice(_ app: XCUIApplication) {
        let menu = app.buttons["reviewer-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let item = app.buttons["review-speech-choice"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 20)); item.tap()
        XCTAssertTrue(app.navigationBars["読み上げ音声"].waitForExistence(timeout: 20), app.debugDescription)
    }
    private func filterEnglishVoices(_ app: XCUIApplication) {
        let search = app.textFields["speech-search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20)); search.tap(); search.typeText("en-US\n")
        let hide = app.buttons["Hide keyboard"]
        if hide.exists && hide.isHittable { hide.tap() }
    }
    private func choose(_ app: XCUIApplication, _ id: String) {
        let item = app.buttons[id].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 20)); item.tap()
        app.buttons["speech-apply"].tap()
        XCTAssertTrue(app.navigationBars["読み上げ音声"].waitForNonExistence(timeout: 30))
    }
    func testInstalledVoiceSelectionPersistsAndQuestionAnswerChoicesAreSeparate() {
        let app = makeApplication()
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
        XCTAssertTrue(app.webViews.staticTexts["AnkiDroid API metadata verified"].waitForExistence(timeout: 30))
        openChoice(app)
        filterEnglishVoices(app)
        let available = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'speech-choice-' AND identifier != 'speech-choice-system' AND identifier != 'speech-choice-off' AND label CONTAINS 'en-US'")).firstMatch
        XCTAssertTrue(available.waitForExistence(timeout: 20), "The picker must expose real installed voices")
        let voice = available.identifier
        available.tap()
        XCTAssertEqual(available.value as? String, "選択中", app.debugDescription)
        let preview = app.buttons["speech-preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 20)); preview.tap()
        let speaking = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "再生中"), object: preview)
        XCTAssertEqual(XCTWaiter.wait(for: [speaking], timeout: 15), .completed, app.debugDescription)
        preview.tap()
        app.buttons["speech-apply"].tap()
        XCTAssertTrue(app.navigationBars["読み上げ音声"].waitForNonExistence(timeout: 30))
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
        XCTAssertTrue(app.buttons["reveal"].waitForExistence(timeout: 30))
        openChoice(app)
        filterEnglishVoices(app)
        XCTAssertEqual(app.buttons[voice].firstMatch.value as? String, "選択中", "Actual voice choice must survive relaunch")
        choose(app, "speech-choice-off")
        tapReady(app.buttons["reveal"])
        XCTAssertTrue(app.buttons["answer-2"].waitForExistence(timeout: 20))
        openChoice(app)
        XCTAssertEqual(app.buttons["speech-choice-system"].firstMatch.value as? String, "選択中")
        XCTAssertNotEqual(app.buttons["speech-choice-off"].firstMatch.value as? String, "選択中", "Front off choice must not leak to back")
        app.buttons["speech-cancel"].tap()
        app.buttons["デッキ"].tap()
        enableTTS(app)
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
        XCTAssertTrue(app.webViews.staticTexts["AnkiDroid API metadata verified"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.navigationBars["読み上げ音声"].exists, "Saved off choice must suppress automatic picker")
        openChoice(app)
        XCTAssertEqual(app.buttons["speech-choice-off"].firstMatch.value as? String, "選択中")
        app.buttons["speech-cancel"].tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testAutomaticSpeechChoiceAndNestedReferencePickerCanCancelAndResume() {
        let app = makeApplication()
        app.launch()
        XCTAssertTrue(app.buttons["add-note"].waitForExistence(timeout: 30)); app.buttons["add-note"].tap()
        let front = app.textViews["note-field-0"], back = app.textViews["note-field-1"]
        XCTAssertTrue(front.waitForExistence(timeout: 20)); front.tap(); front.typeText("Automatic speech next card")
        for _ in 0..<8 { if back.exists && back.isHittable { break }; app.collectionViews["note-form"].swipeUp() }
        XCTAssertTrue(back.waitForExistence(timeout: 20)); back.tap(); back.typeText("Back without native audio")
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30)); app.buttons["note-close"].tap()
        enableTTS(app)
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
        XCTAssertTrue(app.navigationBars["読み上げ音声"].waitForExistence(timeout: 30), "Unconfigured fallback must ask for a voice")
        choose(app, "speech-choice-system")
        XCTAssertTrue(app.buttons["reveal"].waitForExistence(timeout: 20)); tapReady(app.buttons["reveal"])
        XCTAssertTrue(app.buttons["answer-2"].waitForExistence(timeout: 20), app.debugDescription); tapReady(app.buttons["answer-2"])
        XCTAssertTrue(app.webViews.staticTexts["Automatic speech next card"].waitForExistence(timeout: 30))
        tapReady(app.buttons["reveal"])
        XCTAssertTrue(app.navigationBars["読み上げ音声"].waitForExistence(timeout: 30))
        app.buttons["speech-cancel"].tap()
        XCTAssertTrue(app.navigationBars["読み上げ音声"].waitForNonExistence(timeout: 20))
        app.buttons["reviewer-menu"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["自分の声を録音・再生"].firstMatch.tap()
        let reference = app.buttons["voice-reference"]
        XCTAssertTrue(reference.waitForExistence(timeout: 20))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: reference)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        reference.tap()
        XCTAssertTrue(app.navigationBars["読み上げ音声"].waitForExistence(timeout: 30), "Reference fallback must present above its voice panel")
        choose(app, "speech-choice-off")
        XCTAssertTrue(app.navigationBars["自分の声"].waitForExistence(timeout: 20))
        app.navigationBars["自分の声"].buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["answer-2"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.webViews.staticTexts["Back without native audio"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
