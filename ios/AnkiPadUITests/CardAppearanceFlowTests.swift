import XCTest

final class CardAppearanceFlowTests: TypographyTestSupport {
    func testImageOnlyZoomAndVerticalCenterSurviveRelaunch() throws {
        let app = makeApplication()
        app.launch()
        try addNote(front: """
        Display preference verification<br><img id="zoom-img" alt="Zoom check" style="width:100px;height:50px" src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jwZkAAAAASUVORK5CYII="><button onclick="const q=document.getElementById('qa').getBoundingClientRect(),i=document.getElementById('zoom-img');document.getElementById('appearance-result').textContent=(document.body.classList.contains('vertically_centered') &amp;&amp; Math.abs(q.top+q.height/2-innerHeight/2)&lt;6 &amp;&amp; Math.abs(i.getBoundingClientRect().width-110)&lt;3)?'Image and centering verified':'Appearance failed';">Check actual appearance</button><div id="appearance-result"></div>
        """, in: app)
        tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        tapTestMenuAction(titles: ["設定"], in: app)
        _ = try XCTUnwrap(waitForTestControl(app.scrollViews.matching(identifier: "settings-form"), in: app, purpose: .observation))
        let zooms = app.steppers.matching(identifier: "image-zoom")
        revealSettingsControl(zooms.element, in: app)
        let zoom = try XCTUnwrap(waitForTestControl(zooms, in: app, purpose: .observation))
        tapTestControl(zooms.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "-Increment")), in: app)
        requireTestCondition("Image-only zoom reaches110percent", in: app) { zoom.label.contains("110%") }
        let centering = app.switches.matching(identifier: "center-vertically")
        revealSettingsControl(centering.element, in: app)
        _ = waitForTestControl(centering, in: app, purpose: .observation)
        capture("Before vertical card centering switch", in: app)
        setTestSwitch(centering, enabled: true, in: app)
        tapTestControl(app.buttons.matching(identifier: "settings-save"), in: app)
        requireTestCondition("Card display settings saved and closed", in: app) { app.buttons.matching(identifier: "settings-save").count == 0 }
        app.terminate()
        app.launchArguments = []
        app.launch()
        tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
        tapTestControl(app.buttons.matching(identifier: "browser-open"), in: app)
        let fields = app.navigationBars.matching(identifier: "カードブラウザー").searchFields
            .matching(NSPredicate(format: "label == %@", "検索（deck:、tag:、is:due など）"))
        let search = try XCTUnwrap(typeInEmptyTestField(fields, text: "Display preference verification", in: app))
        search.typeText("\n")
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "browser-card-", "Display preference verification"))
        let row = try XCTUnwrap(waitForTestControl(rows, in: app))
        row.press(forDuration: 1)
        tapTestMenuAction(titles: ["プレビュー"], in: app)
        let web = try XCTUnwrap(waitForTestCardWebView(in: app))
        tapTestControl(web.buttons.matching(NSPredicate(format: "label == %@", "Check actual appearance")), in: app)
        requireTestCondition("Real card retains image zoom and vertical centering", in: app) {
            web.staticTexts.matching(NSPredicate(format: "label == %@", "Image and centering verified")).count == 1
        }
        capture("Readable preview with image zoom and vertical centering", in: app)
        XCTAssertEqual(app.alerts.count, 0)
    }
}
