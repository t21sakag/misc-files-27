import XCTest

final class BackendThemeFlowTests: StudyFlowTestSupport {
    func testBundledPagesUseNativeNightThemeAndRemainInteractive() {
        let app = makeApplication()
        app.launchArguments += ["--uitest-backend-theme"]
        app.launch()
        XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
        func choose(_ identifier: String, _ title: String) {
            let item = app.buttons[identifier]
            revealSettingsControl(item, in: app); item.tap(); app.buttons[title].firstMatch.tap()
        }
        func settings(dark: Bool, night: String) {
            app.buttons["collection-menu"].tap(); app.buttons["設定"].tap()
            choose("app-theme-mode", dark ? "ダーク" : "ライト")
            if dark { choose("night-theme", night) }
            app.buttons["settings-save"].tap()
            XCTAssertTrue(app.navigationBars["設定"].waitForNonExistence(timeout: 30))
        }
        func inspect(theme: String, rgb: String, dark: Bool) {
            let button = app.buttons["backend-theme-inspect"]
            XCTAssertTrue(button.waitForExistence(timeout: 30)); button.tap()
            let report = app.staticTexts["backend-theme-report"]
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let value = report.value as? String, let data = value.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
                return json["theme"] as? String == theme && json["night"] as? Bool == dark && json["body"] as? String == rgb
                    && json["bootstrap"] as? String == (dark ? "dark" : "light")
                    && json["scheme"] as? String == (dark ? "dark" : "light")
                    && json["hash"] as? String == (dark ? "#night" : "")
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed, "Observed backend DOM: \(String(describing: report.value))")
            app.buttons["backend-close"].tap()
            XCTAssertTrue(button.waitForNonExistence(timeout: 30))
        }
        for (name, night, dark, rgb) in [("dark", "ダーク", true, "rgb(48, 48, 48)"),
                                        ("black", "ブラック", true, "rgb(0, 0, 0)"),
                                        ("light", "ブラック", false, "rgb(255, 255, 255)")] {
            settings(dark: dark, night: night)
            if name == "dark" {
                app.terminate(); app.launch()
                XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
            }
            app.buttons["collection-menu"].tap(); app.buttons["statistics"].tap()
            XCTAssertTrue(app.webViews.staticTexts["今日"].waitForExistence(timeout: 60), app.debugDescription)
            inspect(theme: name, rgb: rgb, dark: dark)
            app.buttons["deck-1"].press(forDuration: 1); app.buttons["デッキオプション"].tap()
            XCTAssertTrue(app.webViews.staticTexts["FSRS"].waitForExistence(timeout: 60), app.debugDescription)
            inspect(theme: name, rgb: rgb, dark: dark)
        }
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
