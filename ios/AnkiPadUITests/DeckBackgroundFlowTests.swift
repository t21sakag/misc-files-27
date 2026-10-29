import XCTest
import UIKit

final class DeckBackgroundFlowTests: StudyFlowTestSupport {
    func testCurrentDeckHighlightMovesPersistsAndStaysTranslucentOverBackground() {
        let app = makeApplication(); app.launchArguments = []; app.launch()
        let first = app.buttons["deck-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 30))
        // The backend omits an empty default deck once another deck exists.
        // Keep both rows visible while checking selection moves between them.
        app.buttons["add-note"].tap()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20)); front.tap(); front.typeText("Current deck selection verification")
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30)); app.buttons["note-close"].tap()
        func selected(_ item: XCUIElement, _ expected: Bool) {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND selected == %@", NSNumber(value: expected)), object: item)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed, app.debugDescription)
        }
        func settings() { app.buttons["collection-menu"].tap(); app.buttons["設定"].tap() }
        func save() {
            app.buttons["settings-save"].tap()
            XCTAssertTrue(app.navigationBars["設定"].waitForNonExistence(timeout: 30))
        }
        func rowPixel(_ expected: Int) {
            func read() -> [UInt8] {
            let screenshot = app.screenshot().image.cgImage!
            let point = CGPoint(x: app.frame.width * 0.55, y: first.frame.midY)
            let sample = screenshot.cropping(to: CGRect(x: point.x * CGFloat(screenshot.width) / app.frame.width,
                                                        y: point.y * CGFloat(screenshot.height) / app.frame.height, width: 1, height: 1))!
            var bytes = [UInt8](repeating: 0, count: 4)
            bytes.withUnsafeMutableBytes { data in
                let ctx = CGContext(data: data.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
                return bytes
            }
            let matches = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                read().prefix(3).allSatisfy { abs(Int($0) - expected) <= 2 }
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 20), .completed, "Actual selected row pixel: \(read())")
        }
        settings()
        let theme = app.buttons["app-theme-mode"]
        revealSettingsControl(theme, in: app); theme.tap(); app.buttons["ライト"].firstMatch.tap(); save()
        selected(first, true); rowPixel(236)
        app.buttons["collection-menu"].tap(); app.buttons["デッキを作成"].tap()
        app.alerts.textFields.firstMatch.typeText("Selection scope")
        app.alerts.buttons["保存"].tap()
        let other = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'deck-' AND label CONTAINS 'Selection scope'")).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 30)); other.tap()
        XCTAssertTrue(app.buttons["デッキ"].waitForExistence(timeout: 30)); app.buttons["デッキ"].tap()
        selected(other, true); selected(first, false)
        app.terminate(); app.launch()
        XCTAssertTrue(other.waitForExistence(timeout: 30)); selected(other, true); selected(first, false)
        first.tap(); XCTAssertTrue(app.buttons["デッキ"].waitForExistence(timeout: 30)); app.buttons["デッキ"].tap()
        selected(first, true); selected(other, false)
        settings()
        let background = app.buttons["deck-background-open"]
        revealSettingsControl(background, in: app); background.tap()
        let choose = app.buttons["deck-background-photo"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: choose)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed); choose.tap()
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 30)); tapScreenFrame(photo, in: app)
        XCTAssertTrue(app.images["deck-background-preview"].waitForExistence(timeout: 30))
        app.buttons["deck-background-done"].tap(); save()
        // The fixture is RGB248 beneath the first row. Native alpha is the
        // upstream integer truncation floor(255*0.45), composited over that image.
        app.terminate(); app.launch()
        XCTAssertTrue(first.waitForExistence(timeout: 30)); selected(first, true); rowPixel(243)
    }

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
