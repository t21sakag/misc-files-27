import XCTest
import AVFoundation

final class AudioFlowTests: StudyFlowTestSupport {
    @MainActor
    func testCardAudioQueueCompletesOnceAndCancellationDoesNotReplay() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func wave(_ name: String, samples: Int) throws {
            var data = Data()
            func text(_ value: String) { data.append(contentsOf: value.utf8) }
            func u16(_ number: UInt16) { var value = number.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
            func u32(_ number: UInt32) { var value = number.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
            text("RIFF"); u32(UInt32(36 + samples * 2)); text("WAVEfmt "); u32(16)
            u16(1); u16(1); u32(8000); u32(16000); u16(2); u16(16)
            text("data"); u32(UInt32(samples * 2)); data.append(Data(repeating: 0, count: samples * 2))
            try data.write(to: root.appendingPathComponent(name))
        }
        try wave("short.wav", samples: 1600)
        try wave("long.wav", samples: 8000)
        let audio = CardAudio()
        defer { audio.stop() }
        var completions = 0
        let sequence = expectation(description: "Both actual PCM clips finish")
        let start = Date()
        audio.play([["soundOrVideo": "short.wav"], ["soundOrVideo": "short.wav"]], media: root) {
            completions += 1; sequence.fulfill()
        }
        await fulfillment(of: [sequence], timeout: 5)
        XCTAssertEqual(completions, 1)
        XCTAssertGreaterThan(Date().timeIntervalSince(start), 0.25, "A rejected/no-output play must not masquerade as completed playback")
        XCTAssertFalse(audio.isPlaying)
        let cancelled = expectation(description: "Cancelled comparison must not start own recording")
        cancelled.isInverted = true
        audio.play([["soundOrVideo": "long.wav"]], media: root) { cancelled.fulfill() }
        XCTAssertTrue(audio.isPlaying)
        audio.stop()
        let replacement = expectation(description: "New audio completes independently")
        audio.play([["soundOrVideo": "short.wav"]], media: root) { replacement.fulfill() }
        await fulfillment(of: [replacement], timeout: 5)
        await fulfillment(of: [cancelled], timeout: 1.1)
        XCTAssertFalse(audio.isPlaying)
    }

    func testReviewRecordingReferenceComparisonAndTemporaryCleanup() {
        let app = makeApplication()
        app.launch()
        let add = app.buttons["add-note"]
        XCTAssertTrue(add.waitForExistence(timeout: 30)); add.tap()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20)); front.tap(); front.typeText("Next card clears temporary recording")
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30)); app.buttons["note-close"].tap()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
        XCTAssertTrue(app.webViews.staticTexts["AnkiDroid API metadata verified"].waitForExistence(timeout: 30))
        let reveal = app.buttons["reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 30)); reveal.tap()
        XCTAssertTrue(app.buttons["answer-2"].waitForExistence(timeout: 20))
        func openVoice() {
            app.buttons["reviewer-menu"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            app.buttons["自分の声を録音・再生"].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["自分の声"].waitForExistence(timeout: 20))
        }
        openVoice()
        let record = app.buttons["voice-record"]
        XCTAssertTrue(record.waitForExistence(timeout: 20)); record.tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = system.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "許可", "OK"])).firstMatch
        if allow.waitForExistence(timeout: 8) { allow.tap() }
        let stop = app.buttons["voice-stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 20), app.debugDescription)
        let seconds = app.staticTexts["voice-recording-seconds"]
        let captured = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            seconds.exists && (Double(seconds.value as? String ?? "") ?? 0) >= 2.5
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [captured], timeout: 20), .completed)
        stop.tap()
        let replay = app.buttons["voice-replay"]
        XCTAssertTrue(replay.waitForExistence(timeout: 20)); replay.tap()
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "録音を一時停止"), object: replay)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 10), .completed, app.debugDescription)
        replay.tap()
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "録音を再生"), object: replay)
        XCTAssertEqual(XCTWaiter.wait(for: [paused], timeout: 10), .completed)
        app.buttons["voice-compare"].tap()
        let compared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "録音を一時停止"), object: replay)
        XCTAssertEqual(XCTWaiter.wait(for: [compared], timeout: 10), .completed)
        app.navigationBars["自分の声"].buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["answer-2"].waitForExistence(timeout: 20), "Recording must not change reviewer state")
        openVoice()
        XCTAssertTrue(replay.waitForExistence(timeout: 20), "Temporary recording survives closing its panel")
        app.navigationBars["自分の声"].buttons["閉じる"].tap()
        app.buttons["answer-2"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Next card clears temporary recording"].waitForExistence(timeout: 30))
        openVoice()
        XCTAssertFalse(replay.exists, "Advancing to another card must remove the old temporary recording")
        XCTAssertTrue(record.exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
