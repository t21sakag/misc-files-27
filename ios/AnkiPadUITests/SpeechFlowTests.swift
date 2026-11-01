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
    private func enableTTS(_ app: XCUIApplication) {
        tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        tapTestMenuAction(titles: ["設定"], in: app)
        let toggle = app.switches.matching(identifier: "tts-enabled")
        revealSettingsControl(toggle.element, in: app)
        guard setTestSwitch(toggle, enabled: true, in: app) else { return }
        tapTestControl(app.buttons.matching(identifier: "settings-save"), in: app)
        requireTestCondition("Settings close after saving speech enablement", in: app) {
            !app.navigationBars["設定"].exists
        }
    }
    private func openChoice(_ app: XCUIApplication) {
        tapTestControl(app.buttons.matching(identifier: "reviewer-menu"), in: app)
        tapTestMenuAction(titles: ["読み上げ音声を選択"], in: app)
        waitForTestControl(app.navigationBars.matching(identifier: "読み上げ音声"), in: app, purpose: .observation)
    }
    private func filterEnglishVoices(_ app: XCUIApplication) {
        guard let search = typeInEmptyTestField(app.textFields.matching(identifier: "speech-search"), text: "en-US", in: app) else { return }
        // Submit separately: the newline is an action, not search field content.
        search.typeText("\n")
        dismissTestKeyboard(in: app)
    }
    private func closeChoice(_ app: XCUIApplication, action: String) {
        tapTestControl(app.buttons.matching(identifier: action), in: app)
        requireTestCondition("Speech picker closes after " + action, in: app) {
            !app.navigationBars["読み上げ音声"].exists
        }
    }
    private func choose(_ app: XCUIApplication, _ id: String) {
        tapTestControl(app.buttons.matching(identifier: id), in: app, form: app.collectionViews["speech-voices-list"])
        closeChoice(app, action: "speech-apply")
    }
    private func assertChoice(_ app: XCUIApplication, _ id: String, selected: Bool = true) {
        guard let row = waitForTestControl(app.buttons.matching(identifier: id), in: app,
                                          form: app.collectionViews["speech-voices-list"], purpose: .observation) else { return }
        XCTAssertEqual(row.value as? String == "選択中", selected, "Saved speech choice: " + id)
    }
    func testInstalledVoiceSelectionPersistsAndQuestionAnswerChoicesAreSeparate() throws {
        let app = makeApplication()
        // Exercise the real editor with short speech content. The general API
        // fixture includes long prose/math; its playback length is unrelated to
        // voice selection. Do not inject preferences, voices or a completion.
        let sample = "This is a voice sample for checking that the selected installed speech voice plays correctly and finishes normally."
        app.launchArguments = ["--uitest-speech-choice"]
        app.launch()
        tapTestControl(app.buttons.matching(identifier: "add-note"), in: app)
        let form = app.collectionViews["note-form"]
        typeInEmptyTestField(app.textViews.matching(identifier: "note-field-0"), text: sample, in: app, form: form)
        typeInEmptyTestField(app.textViews.matching(identifier: "note-field-1"), text: "Answer example.", in: app, form: form)
        tapTestControl(app.buttons.matching(identifier: "note-save"), in: app)
        waitForTestControl(app.staticTexts.matching(identifier: "note-added"), in: app, purpose: .observation)
        tapTestControl(app.buttons.matching(identifier: "note-close"), in: app)
        tapTestControl(app.buttons.matching(identifier: "deck-1"), in: app)
        waitForTestControl(app.webViews.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern([sample]))), in: app, purpose: .observation)
        openChoice(app)
        filterEnglishVoices(app)
        let installed = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'speech-choice-' AND identifier != 'speech-choice-system' AND identifier != 'speech-choice-off' AND label CONTAINS 'en-US'"))
        requireTestCondition("Real installed English voices are listed", in: app) { installed.count > 0 }
        // Collect semantic IDs as data, then resolve the selected ID uniquely.
        // Never choose a first duplicate accessibility element for an action.
        let ids = Set(installed.allElementsBoundByIndex.map { $0.identifier }).sorted()
        let voice = try XCTUnwrap(ids.first, "The picker must expose a real installed voice")
        tapTestControl(app.buttons.matching(identifier: voice), in: app, form: app.collectionViews["speech-voices-list"])
        assertChoice(app, voice)
        guard let counter = waitForTestControl(app.staticTexts.matching(identifier: "native-speech-completions"), in: app, purpose: .observation),
              let completedVoice = waitForTestControl(app.staticTexts.matching(identifier: "native-speech-completed-voice"), in: app, purpose: .observation) else { return }
        let before = try XCTUnwrap(Int(counter.value as? String ?? ""))
        guard let preview = tapTestControl(app.buttons.matching(identifier: "speech-preview"), in: app) else { return }
        requireTestCondition("Selected voice preview starts", in: app, timeout: 15) { preview.value as? String == "再生中" }
        requireTestCondition("Selected installed voice actually completes native synthesis", in: app) {
            (Int(counter.value as? String ?? "") ?? 0) > before
                && completedVoice.value as? String == String(voice.dropFirst("speech-choice-".count))
                && preview.value as? String == "停止中"
        }
        // Preserve independent coverage of actively stopping a second preview.
        tapTestControl(app.buttons.matching(identifier: "speech-preview"), in: app)
        requireTestCondition("Second preview starts before stop", in: app, timeout: 15) { preview.value as? String == "再生中" }
        tapTestControl(app.buttons.matching(identifier: "speech-preview"), in: app)
        requireTestCondition("Stop ends the preview queue", in: app) { preview.value as? String == "停止中" }
        closeChoice(app, action: "speech-apply")
        app.terminate(); app.launch()
        tapTestControl(app.buttons.matching(identifier: "deck-1"), in: app)
        waitForTestControl(app.buttons.matching(identifier: "reveal"), in: app)
        openChoice(app)
        filterEnglishVoices(app)
        assertChoice(app, voice)
        choose(app, "speech-choice-off")
        tapTestControl(app.buttons.matching(identifier: "reveal"), in: app)
        waitForTestControl(app.buttons.matching(identifier: "answer-2"), in: app)
        openChoice(app)
        assertChoice(app, "speech-choice-system")
        assertChoice(app, "speech-choice-off", selected: false)
        closeChoice(app, action: "speech-cancel")
        tapTestControl(app.buttons.matching(identifier: "デッキ"), in: app)
        enableTTS(app)
        app.terminate(); app.launch()
        tapTestControl(app.buttons.matching(identifier: "deck-1"), in: app)
        waitForTestControl(app.webViews.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern([sample]))), in: app, purpose: .observation)
        XCTAssertFalse(app.navigationBars["読み上げ音声"].exists, "Saved off choice must suppress automatic picker")
        openChoice(app)
        assertChoice(app, "speech-choice-off")
        closeChoice(app, action: "speech-cancel")
        XCTAssertFalse(app.alerts.element.exists)
    }

    func testAutomaticSpeechChoiceAndNestedReferencePickerCanCancelAndResume() {
        let app = makeApplication()
        app.launch()
        tapTestControl(app.buttons.matching(identifier: "add-note"), in: app)
        let form = app.collectionViews["note-form"]
        typeInEmptyTestField(app.textViews.matching(identifier: "note-field-0"), text: "Automatic speech next card", in: app, form: form)
        typeInEmptyTestField(app.textViews.matching(identifier: "note-field-1"), text: "Back without native audio", in: app, form: form)
        tapTestControl(app.buttons.matching(identifier: "note-save"), in: app)
        waitForTestControl(app.staticTexts.matching(identifier: "note-added"), in: app, purpose: .observation)
        tapTestControl(app.buttons.matching(identifier: "note-close"), in: app)
        enableTTS(app)
        tapTestControl(app.buttons.matching(identifier: "deck-1"), in: app)
        waitForTestControl(app.navigationBars.matching(identifier: "読み上げ音声"), in: app, purpose: .observation)
        choose(app, "speech-choice-system")
        tapTestControl(app.buttons.matching(identifier: "reveal"), in: app)
        tapTestControl(app.buttons.matching(identifier: "answer-2"), in: app)
        waitForTestControl(app.webViews.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern(["Automatic speech next card"]))), in: app, purpose: .observation)
        tapTestControl(app.buttons.matching(identifier: "reveal"), in: app)
        waitForTestControl(app.navigationBars.matching(identifier: "読み上げ音声"), in: app, purpose: .observation)
        closeChoice(app, action: "speech-cancel")
        tapTestControl(app.buttons.matching(identifier: "reviewer-menu"), in: app)
        tapTestMenuAction(titles: ["自分の声を録音・再生"], in: app)
        tapTestControl(app.buttons.matching(identifier: "voice-reference"), in: app)
        waitForTestControl(app.navigationBars.matching(identifier: "読み上げ音声"), in: app, purpose: .observation)
        choose(app, "speech-choice-off")
        waitForTestControl(app.navigationBars.matching(identifier: "自分の声"), in: app, purpose: .observation)
        tapTestControl(app.navigationBars["自分の声"].buttons.matching(identifier: "閉じる"), in: app)
        waitForTestControl(app.buttons.matching(identifier: "answer-2"), in: app)
        waitForTestControl(app.webViews.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ControlLabelMatch.pattern(["Back without native audio"]))), in: app, purpose: .observation)
        XCTAssertFalse(app.alerts.element.exists)
    }
}
