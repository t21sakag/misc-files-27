import XCTest
import UIKit

final class ThemePanelFlowTests: StudyFlowTestSupport {
    func testDarkAndBlackThemesReachAccountProfilesEditorAndMaintenance() {
        let app = makeApplication(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30))
        func background(_ identifier: String, _ expected: Int) {
            let form = app.collectionViews[identifier]
            XCTAssertTrue(form.waitForExistence(timeout: 30), app.debugDescription)
            func pixel() -> [UInt8] {
                let frame = form.frame, shot = app.screenshot().image.cgImage!
                let x = (frame.minX + 3 - app.frame.minX) * CGFloat(shot.width) / app.frame.width
                let y = (frame.midY - app.frame.minY) * CGFloat(shot.height) / app.frame.height
                let sample = shot.cropping(to: CGRect(x: x.rounded(.down), y: y.rounded(.down), width: 1, height: 1))!
                var bytes = [UInt8](repeating: 0, count: 4)
                bytes.withUnsafeMutableBytes { data in
                    let ctx = CGContext(data: data.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    ctx.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                }
                return bytes
            }
            let matches = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                pixel().prefix(3).allSatisfy { abs(Int($0) - expected) <= 5 }
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 20), .completed, "Actual \(identifier) pixel: \(pixel())")
        }
        for (title, expected) in [("ダーク", 48), ("ブラック", 0)] {
            app.buttons["collection-menu"].tap(); app.buttons["設定"].tap()
            let mode = app.buttons["app-theme-mode"]
            revealSettingsControl(mode, in: app); mode.tap(); app.buttons["ダーク"].firstMatch.tap()
            let night = app.buttons["night-theme"]
            revealSettingsControl(night, in: app); night.tap(); app.buttons[title].firstMatch.tap()
            app.buttons["settings-save"].tap()
            XCTAssertTrue(app.navigationBars["設定"].waitForNonExistence(timeout: 30))
            app.terminate(); app.launch(); XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30))
            app.buttons["ankiweb-account"].tap(); background("account-form", expected)
            app.navigationBars["AnkiWeb"].buttons["閉じる"].tap()
            XCTAssertTrue(app.navigationBars["AnkiWeb"].waitForNonExistence(timeout: 30))
            app.buttons["collection-menu"].tap(); app.buttons["profiles-open"].tap(); background("profiles-form", expected)
            app.buttons["profiles-close"].tap()
            XCTAssertTrue(app.navigationBars["プロファイル"].waitForNonExistence(timeout: 30))
            app.buttons["add-note"].tap(); background("note-form", expected); app.buttons["note-close"].tap()
            XCTAssertTrue(app.navigationBars["ノートを追加"].waitForNonExistence(timeout: 30))
            openMaintenance(app); background("maintenance-form", expected); app.buttons["maintenance-close"].tap()
            XCTAssertTrue(app.navigationBars["バックアップとチェック"].waitForNonExistence(timeout: 30))
        }
    }
}
