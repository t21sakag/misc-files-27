import XCTest

final class TypographyFlowTests: TypographyTestSupport {
    func testReadableNativeBrowserAndEditorInBothOrientations() throws {
        let app = application()
        defer { XCUIDevice.shared.orientation = .portrait }
        let frontText = "English sentence 日本語の文章"
        let backText = "日本語の意味"
        tapTestControl(app.buttons.matching(identifier: "add-note"), in: app)
        let form = app.collectionViews["note-form"]
        let editor = try XCTUnwrap(typeInEmptyTestField(app.textViews.matching(identifier: "note-field-0"), text: frontText, in: app, form: form))
        XCTAssertGreaterThanOrEqual(editor.frame.height, 130)
        typeInEmptyTestField(app.textViews.matching(identifier: "note-field-1"), text: backText, in: app, form: form)
        dismissTestKeyboard(in: app)
        capture("Readable native editor English and Japanese", in: app)
        tapTestControl(app.buttons.matching(identifier: "note-save"), in: app)
        _ = waitForTestControl(app.staticTexts.matching(identifier: "note-added"), in: app, purpose: .observation)
        tapTestControl(app.buttons.matching(identifier: "note-close"), in: app)
        capture("Readable deck list", in: app)
        openBrowser(app)
        let front = try XCTUnwrap(waitForTestControl(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "browser-front-", frontText)), in: app, purpose: .observation))
        let back = try XCTUnwrap(waitForTestControl(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "browser-back-", backText)), in: app, purpose: .observation))
        let metadata = try XCTUnwrap(waitForTestControl(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "browser-metadata-", "-template")), in: app, purpose: .observation))
        capture("Browser font measurements before assertions", in: app)
        XCTAssertGreaterThanOrEqual(front.frame.height, 22)
        XCTAssertGreaterThanOrEqual(back.frame.height, 20)
        XCTAssertGreaterThanOrEqual(metadata.frame.height, 16)
        capture("Readable browser portrait", in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        requireTestCondition("Landscape browser lays out enlarged content", in: app) {
            app.frame.width > app.frame.height && front.isHittable && back.isHittable
                && front.frame.maxX <= app.frame.maxX && back.frame.maxX <= app.frame.maxX
        }
        capture("Readable browser landscape", in: app)
        tapTestControl(app.navigationBars.buttons.matching(NSPredicate(format: "label == %@", "閉じる")), in: app)
        tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        tapTestMenuAction(titles: ["設定"], in: app)
        _ = waitForTestControl(app.buttons.matching(identifier: "settings-save"), in: app)
        capture("Readable settings explanatory text", in: app)
        tapTestControl(app.buttons.matching(identifier: "settings-save"), in: app)
        requireTestCondition("Settings closes after saving", in: app) { app.buttons.matching(identifier: "settings-save").count == 0 }
    }

    func testCardTextGrowsWithoutChangingImageWidth() throws {
        let app = application()
        defer { XCUIDevice.shared.orientation = .portrait }
        let html = """
        <div id="read-en" style="font-family:Arial;font-size:20px;white-space:nowrap">English text</div>
        <div id="read-ja" style="font-family:Arial;font-size:20px;white-space:nowrap">日本語を読む</div>
        <img id="read-image" alt="Typography image" style="width:100px;height:50px" src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jwZkAAAAASUVORK5CYII="><br>
        <button onclick="const canvas=document.createElement('canvas'),ctx=canvas.getContext('2d');ctx.font='20px Arial';const metrics=['read-en','read-ja'].map(id=>{const e=document.getElementById(id),r=document.createRange();r.selectNodeContents(e);const box=r.getBoundingClientRect();return {ratio:box.width/ctx.measureText(e.textContent).width,height:box.height,top:box.top,bottom:box.bottom};});const image=document.getElementById('read-image').getBoundingClientRect();const ok=metrics.every(m=>m.ratio>1.30 &amp;&amp; m.ratio<1.65 &amp;&amp; m.height>=26) &amp;&amp; metrics[1].top>=metrics[0].bottom+2 &amp;&amp; Math.abs(image.width-100)<1 &amp;&amp; document.documentElement.scrollWidth<=innerWidth+1;document.getElementById('read-result').textContent=ok?'Typography verified '+(innerWidth>innerHeight?'landscape':'portrait'):'Typography failed '+JSON.stringify({metrics,imageWidth:image.width,adjust:getComputedStyle(document.documentElement).webkitTextSizeAdjust});">Measure readable text</button>
        <div id="read-result" aria-live="polite"></div>
        """
        try addNote(front: html, back: "English answer 日本語の答え", in: app)
        tapTestControl(app.buttons.matching(identifier: "deck-1"), in: app)
        let web = try XCTUnwrap(waitForTestCardWebView(in: app))
        tapTestControl(web.buttons.matching(NSPredicate(format: "label == %@", "Measure readable text")), in: app)
        requireTestCondition("Real WebKit renders enlarged English and Japanese glyphs", in: app) {
            web.staticTexts.matching(NSPredicate(format: "label == %@", "Typography verified portrait")).count == 1
        }
        let image = try XCTUnwrap(waitForTestControl(web.images.matching(NSPredicate(format: "label == %@", "Typography image")), in: app, purpose: .observation))
        XCTAssertEqual(image.frame.width, 100, accuracy: 2)
        capture("Readable card English Japanese and fixed image", in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        requireTestCondition("Reviewer rotates to landscape", in: app) { app.frame.width > app.frame.height }
        tapTestControl(web.buttons.matching(NSPredicate(format: "label == %@", "Measure readable text")), in: app)
        requireTestCondition("Landscape retains the same text scaling and image size", in: app) {
            web.staticTexts.matching(NSPredicate(format: "label == %@", "Typography verified landscape")).count == 1
        }
        capture("Readable card landscape", in: app)
        tapTestControl(app.buttons.matching(identifier: "reveal"), in: app)
        _ = waitForTestControl(web.staticTexts.matching(NSPredicate(format: "label == %@", "English answer 日本語の答え")), in: app, purpose: .observation)
        capture("Readable card answer", in: app)
    }

    func testVisualEditorLargerTextPreservesOriginalHTML() throws {
        let app = application()
        tapTestControl(app.buttons.matching(identifier: "add-note"), in: app)
        let form = app.collectionViews["note-form"]
        let original = "<b>English sentence</b> 日本語の文章"
        typeInEmptyTestField(app.textViews.matching(identifier: "note-field-0"), text: original, in: app, form: form)
        let toggle = app.switches.matching(NSPredicate(format: "label == %@", "ビジュアル編集"))
        waitForTestControl(toggle, in: app, form: form, purpose: .observation)
        capture("Before visual editor font layout", in: app)
        setTestSwitch(toggle, enabled: true, in: app)
        let roots = app.descendants(matching: .other).children(matching: .webView).matching(identifier: "note-field-0-web")
        let visual = try XCTUnwrap(waitForTestControl(roots, in: app, purpose: .observation))
        XCTAssertGreaterThanOrEqual(visual.frame.height, 150)
        let fieldContent = visual.textViews.matching(NSPredicate(format: "label == %@", "note-field-0"))
        let rich = try XCTUnwrap(waitForTestControl(fieldContent, in: app, purpose: .observation))
        requireTestCondition("Visual editor renders both languages", in: app) {
            guard let value = rich.value as? String else { return false }
            return value.contains("English sentence") && value.contains("日本語の文章")
        }
        capture("Readable visual editor", in: app)
        waitForTestControl(toggle, in: app, form: form, purpose: .observation)
        setTestSwitch(toggle, enabled: false, in: app)
        let raw = try XCTUnwrap(waitForTestControl(app.textViews.matching(identifier: "note-field-0"), in: app, form: form, purpose: .observation))
        XCTAssertEqual(raw.value as? String, original)
        typeInEmptyTestField(app.textViews.matching(identifier: "note-field-1"), text: "日本語の意味", in: app, form: form)
        tapTestControl(app.buttons.matching(identifier: "note-save"), in: app)
        _ = waitForTestControl(app.staticTexts.matching(identifier: "note-added"), in: app, purpose: .observation)
        tapTestControl(app.buttons.matching(identifier: "note-close"), in: app)
        app.terminate()
        app.launch()
        openBrowser(app)
        _ = waitForTestControl(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@ AND label CONTAINS %@", "browser-front-", "English sentence", "日本語の文章")), in: app, purpose: .observation)
        capture("Saved text after visual editor typography", in: app)
    }
}
