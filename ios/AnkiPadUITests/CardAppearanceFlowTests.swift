import XCTest

final class CardAppearanceFlowTests: StudyFlowTestSupport {
    func testImageOnlyZoomAndVerticalCenterSurviveRelaunch() {
        let app = makeApplication()
        app.launch()
        XCTAssertTrue(app.buttons["add-note"].waitForExistence(timeout: 30)); app.buttons["add-note"].tap()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20)); front.tap()
        front.typeText("""
        Display preference verification<br><img id="zoom-img" alt="Zoom check" style="width:100px;height:50px" src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jwZkAAAAASUVORK5CYII="><button onclick="const q=document.getElementById('qa').getBoundingClientRect(),i=document.getElementById('zoom-img');document.getElementById('appearance-result').textContent=(document.body.classList.contains('vertically_centered') &amp;&amp; Math.abs(q.top+q.height/2-innerHeight/2)&lt;6 &amp;&amp; Math.abs(i.getBoundingClientRect().width-110)&lt;3)?'Image and centering verified':'Appearance failed';">Check actual appearance</button><div id="appearance-result"></div>
        """)
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30)); app.buttons["note-close"].tap()
        app.buttons["collection-menu"].tap(); app.buttons["設定"].tap()
        let zoom = app.steppers["image-zoom"]
        revealSettingsControl(zoom, in: app)
        zoom.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()
        XCTAssertTrue(zoom.label.contains("110%"), app.debugDescription)
        let outer = app.switches["center-vertically"]
        revealSettingsControl(outer, in: app)
        let toggle = outer.switches.firstMatch.exists ? outer.switches.firstMatch : outer
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [on], timeout: 10), .completed)
        app.buttons["settings-save"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForNonExistence(timeout: 30))
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
        app.buttons["collection-menu"].tap(); app.buttons["browser-open"].tap()
        let search = app.searchFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", "検索（")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20)); search.tap(); search.typeText("Display preference verification")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'browser-card-' AND label CONTAINS 'Display preference verification'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30)); row.press(forDuration: 1); app.buttons["プレビュー"].tap()
        let check = app.webViews.buttons["Check actual appearance"]
        XCTAssertTrue(check.waitForExistence(timeout: 30)); check.tap()
        XCTAssertTrue(app.webViews.staticTexts["Image and centering verified"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
