import XCTest
import UIKit

final class DeckBackgroundFlowTests: StudyFlowTestSupport {
    func testBackgroundImagePersistsAndCancellingSelectionOrRemovalKeepsSavedImage() {
        let app = makeApplication()
        app.launchArguments = []
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        func settings() {
            app.buttons["collection-menu"].tap(); app.buttons["設定"].tap()
        }
        func openBackground() {
            let link = app.buttons["deck-background-open"]
            revealSettingsControl(link, in: app); link.tap()
            let photo = app.buttons["deck-background-photo"]
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true AND hittable == true"), object: photo)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        }
        func choose() {
            app.buttons["deck-background-photo"].tap()
            let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
            XCTAssertTrue(photo.waitForExistence(timeout: 30)); tapScreenFrame(photo, in: app)
            let preview = app.images["deck-background-preview"]
            XCTAssertTrue(preview.waitForExistence(timeout: 30))
            XCTAssertEqual(preview.value as? String, "512 × 384")
            app.buttons["deck-background-done"].tap()
        }
        func remove() {
            app.buttons["deck-background-remove"].tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 20))
            app.alerts.buttons["削除"].tap()
            XCTAssertTrue(app.staticTexts["deck-background-none"].waitForExistence(timeout: 20))
            app.buttons["deck-background-done"].tap()
        }
        func save() {
            app.buttons["settings-save"].tap()
            XCTAssertTrue(app.navigationBars["設定"].waitForNonExistence(timeout: 30))
        }
        func pixelAt(_ point: CGPoint) -> [Int] {
            let screenshot = app.screenshot().image.cgImage!
            let scaleX = CGFloat(screenshot.width) / app.frame.width, scaleY = CGFloat(screenshot.height) / app.frame.height
            var pixel = [UInt8](repeating: 0, count: 4)
            let sample = screenshot.cropping(to: CGRect(x: (point.x * scaleX).rounded(.down), y: (point.y * scaleY).rounded(.down), width: 1, height: 1))!
            pixel.withUnsafeMutableBytes { bytes in
                let ctx = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.interpolationQuality = .none
                ctx.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            return pixel.prefix(3).map(Int.init)
        }
        func assertBackground(_ visible: Bool) {
            // The shared 512x384 geometric photo has a blue circle at (352,232).
            // Predict its screen position using the actual list frame and the
            // upstream center-crop rule, then inspect the rendered pixel.
            let list = app.collectionViews.firstMatch.frame
            let scale = max(list.width / 512, list.height / 384)
            let point = CGPoint(x: list.midX + (352 - 256) * scale, y: list.midY + (232 - 192) * scale)
            let expected = visible ? [45, 95, 220] : [255, 255, 255]
            let matches = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                zip(pixelAt(point), expected).allSatisfy { abs($0.0 - $0.1) <= 5 }
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 20), .completed, "Actual background pixel: \(pixelAt(point)) at \(point)")
        }
        settings()
        let appearance = app.buttons["app-theme-mode"]
        revealSettingsControl(appearance, in: app); appearance.tap(); app.buttons["ライト"].firstMatch.tap(); save()
        settings(); openBackground(); choose()
        app.navigationBars["設定"].buttons["キャンセル"].tap()
        assertBackground(false)
        settings(); openBackground()
        XCTAssertTrue(app.staticTexts["deck-background-none"].exists, "Cancelled selection must not persist")
        choose(); save(); assertBackground(true)
        app.terminate(); app.launch()
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); assertBackground(true)
        settings(); openBackground(); remove()
        app.navigationBars["設定"].buttons["キャンセル"].tap()
        assertBackground(true)
        settings(); openBackground(); remove(); save()
        app.terminate(); app.launch()
        XCTAssertTrue(deck.waitForExistence(timeout: 30)); assertBackground(false)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
