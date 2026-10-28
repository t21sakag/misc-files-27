import XCTest

final class TemplateAudioFlowTests: StudyFlowTestSupport {
    func testTemplateMicrophoneConsentCancelCaptureStopAndRevoke() {
        let app = makeApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["add-note"].waitForExistence(timeout: 30)); app.buttons["add-note"].tap()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20)); front.tap()
        let captureHTML = """
        <button id="start-capture">Start template microphone</button><button id="stop-capture">Stop template microphone</button><button id="check-tracks">Check template tracks</button><div id="capture-status" aria-live="polite">Capture ready</div><script>window.addEventListener('error',e=>{document.getElementById('capture-status').textContent='Capture script error: '+e.message;});</script><script>(()=>{let stream,recorder,chunks=[],attempt=0;const out=document.getElementById('capture-status');document.getElementById('start-capture').onclick=async()=>{const current=++attempt;out.textContent='Capture requesting '+current;try{stream=await navigator.mediaDevices.getUserMedia({audio:true});chunks=[];recorder=new MediaRecorder(stream);recorder.ondataavailable=e=>{if(e.data.size)chunks.push(e.data);};recorder.onstop=()=>{const blob=new Blob(chunks);out.textContent=blob.size>0&&stream.getTracks().every(t=>t.readyState==='ended')?'Capture saved and tracks ended':'Capture stop failed';};recorder.start(100);out.textContent=stream.getAudioTracks().some(t=>t.readyState==='live')?'Capture live':'Capture not live';}catch(e){out.textContent='Capture rejected '+current+': '+e.name;}};document.getElementById('check-tracks').onclick=()=>{out.textContent=stream&&stream.getTracks().every(t=>t.readyState==='ended')?'All tracks ended':'Tracks still live';};document.getElementById('stop-capture').onclick=()=>{if(recorder?.state==='recording'){recorder.stop();stream.getTracks().forEach(t=>t.stop());}};out.textContent='Capture script ready';})();</script>
        """
        front.typeText(captureHTML)
        XCTAssertEqual(front.value as? String, captureHTML, "The template script must be entered without text substitutions")
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30)); app.buttons["note-close"].tap()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
        let start = app.webViews.buttons["Start template microphone"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        XCTAssertTrue(app.webViews.staticTexts["Capture script ready"].waitForExistence(timeout: 30), app.debugDescription)
        waitUntilHittable(start); start.tap()
        let consent = app.alerts["カードの録音"]
        XCTAssertTrue(consent.waitForExistence(timeout: 20), app.debugDescription); consent.buttons["キャンセル"].tap()
        let rejected = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Capture rejected 1:'")).firstMatch
        XCTAssertTrue(rejected.waitForExistence(timeout: 20), app.debugDescription)
        start.tap()
        let secondRejected = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Capture rejected 2:'")).firstMatch
        XCTAssertTrue(secondRejected.waitForExistence(timeout: 20))
        XCTAssertFalse(consent.exists, "Declining must not cause repeated prompts in this view")
        app.buttons["デッキ"].tap(); XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 30)); start.tap()
        XCTAssertTrue(consent.waitForExistence(timeout: 20), app.debugDescription); consent.buttons["許可"].tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "許可", "OK"])).firstMatch
        if allow.waitForExistence(timeout: 8) { allow.tap() }
        XCTAssertTrue(app.webViews.staticTexts["Capture live"].waitForExistence(timeout: 30), app.debugDescription)
        app.webViews.buttons["Stop template microphone"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Capture saved and tracks ended"].waitForExistence(timeout: 30), app.debugDescription)
        start.tap()
        XCTAssertTrue(app.webViews.staticTexts["Capture live"].waitForExistence(timeout: 30))
        XCUIDevice.shared.press(.home)
        app.activate()
        let checkTracks = app.webViews.buttons["Check template tracks"]
        XCTAssertTrue(checkTracks.waitForExistence(timeout: 30)); checkTracks.tap()
        XCTAssertTrue(app.webViews.staticTexts["All tracks ended"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["デッキ"].tap()
        app.buttons["collection-menu"].tap(); app.buttons["設定"].tap()
        let outer = app.switches["allow-template-audio-recording"]
        revealSettingsControl(outer, in: app)
        let toggle = outer.switches.firstMatch.exists ? outer.switches.firstMatch : outer
        XCTAssertEqual(toggle.value as? String, "1", "Successful card consent persists the app permission")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        app.buttons["settings-save"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForNonExistence(timeout: 30))
        app.terminate(); app.launch()
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); deck.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 30)); start.tap()
        XCTAssertTrue(consent.waitForExistence(timeout: 20), "Revoking must require consent again")
        consent.buttons["キャンセル"].tap()
        XCTAssertTrue(rejected.waitForExistence(timeout: 20))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
