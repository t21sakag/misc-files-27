import XCTest
import UIKit

final class ThemeFlowTests: StudyFlowTestSupport {
    func testDayAndNightThemeChoicesPersistAndStyleNativeAndCardSurfaces() {
        let app = makeApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["add-note"].waitForExistence(timeout: 30)); app.buttons["add-note"].tap()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20)); front.tap()
        front.typeText("""
        <style>body.ankidroid_dark_mode{color:rgb(250,200,100)}</style><button style="min-height:48px;padding:12px" id="theme-inspect">Inspect card theme</button><div id="theme-result" aria-live="polite"></div><script>document.getElementById('theme-inspect').onclick=()=>{const b=document.body,t=b.dataset.studyTheme,c=getComputedStyle(b),dark=matchMedia('(prefers-color-scheme:dark)').matches,night=b.classList.contains('night_mode')&&b.classList.contains('nightMode');let ok=false;if(t==='dark')ok=dark&&night&&b.classList.contains('ankidroid_dark_mode')&&c.backgroundColor==='rgb(48, 48, 48)'&&c.color==='rgb(250, 200, 100)';if(t==='black')ok=dark&&night&&!b.classList.contains('ankidroid_dark_mode')&&c.backgroundColor==='rgb(0, 0, 0)';if(t==='plain')ok=!dark&&!night&&b.classList.contains('ankidroid_plain_mode')&&c.backgroundColor==='rgb(255, 255, 255)';if(t==='eink')ok=!dark&&!night&&!b.classList.contains('ankidroid_plain_mode')&&c.backgroundColor==='rgb(255, 255, 255)';document.getElementById('theme-result').textContent=ok?'Theme verified '+t:'Theme failed '+t+' '+c.backgroundColor+' '+c.color;};</script>
        """)
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30)); app.buttons["note-close"].tap()
        func openSettings() {
            XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
            app.buttons["collection-menu"].tap(); app.buttons["設定"].tap()
        }
        func pick(_ identifier: String, _ title: String) {
            let picker = app.buttons[identifier]
            revealSettingsControl(picker, in: app); picker.tap()
            app.buttons[title].firstMatch.tap()
        }
        func saveAndRelaunch() {
            app.buttons["settings-save"].tap()
            XCTAssertTrue(app.navigationBars["設定"].waitForNonExistence(timeout: 30))
            app.terminate(); app.launch()
            XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30))
        }
        func nativeBackground(_ expected: UInt8) {
            let image = app.screenshot().image.cgImage!
            var pixel = [UInt8](repeating: 0, count: 4)
            pixel.withUnsafeMutableBytes { bytes in
                let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.interpolationQuality = .none
                context.translateBy(x: -CGFloat(Int(Double(image.width) * 0.01)), y: -CGFloat(image.height / 2))
                context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
            }
            for channel in pixel.prefix(3) { XCTAssertLessThanOrEqual(abs(Int(channel) - Int(expected)), 5, "Actual native deck-list background: \(pixel)") }
        }
        func inspectCard(_ expected: String) {
            app.buttons["deck-1"].tap()
            let inspect = app.webViews.buttons["Inspect card theme"]
            XCTAssertTrue(inspect.waitForExistence(timeout: 30)); waitUntilHittable(inspect)
            inspect.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(app.webViews.staticTexts["Theme verified " + expected].waitForExistence(timeout: 20), app.debugDescription)
            app.buttons["デッキ"].tap()
        }
        openSettings(); pick("app-theme-mode", "ダーク"); pick("night-theme", "ダーク")
        saveAndRelaunch(); nativeBackground(48); inspectCard("dark")
        openSettings(); pick("night-theme", "ブラック")
        saveAndRelaunch(); nativeBackground(0); inspectCard("black")
        openSettings(); pick("app-theme-mode", "ライト"); pick("day-theme", "プレーン")
        saveAndRelaunch(); nativeBackground(255); inspectCard("plain")
        openSettings(); pick("day-theme", "E Ink")
        saveAndRelaunch(); nativeBackground(255); inspectCard("eink")
        openSettings(); pick("day-theme", "プレーン")
        app.navigationBars["設定"].buttons["キャンセル"].tap()
        inspectCard("eink")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
