import XCTest

final class MediaFlowTests: StudyFlowTestSupport {
    func testZImageOcclusionCanBeCreatedFromPhoto() {
        let app = makeApplication()
        app.launchArguments = ["--uitest-fixture"]
        app.launch()
        let deck = app.buttons["deck-1"]
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        func firstNumber(_ value: String) -> Int {
            value.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init).first ?? -1
        }
        let original = firstNumber(deck.label)
        XCTAssertGreaterThanOrEqual(original, 0)
        let menu = app.buttons["collection-menu"]
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["add-occlusion"].tap()
        let photos = app.buttons["occlusion-select-photo"]
        XCTAssertTrue(photos.waitForExistence(timeout: 20))
        photos.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "キャンセル"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 30), app.debugDescription)
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 30), app.debugDescription)
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 30), app.debugDescription)
        let imageReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            web.images.allElementsBoundByIndex.contains { $0.frame.width > 100 && $0.frame.height > 100 }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [imageReady], timeout: 45), .completed, app.debugDescription)
        guard let image = web.images.allElementsBoundByIndex.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { XCTFail(app.debugDescription); return }
        image.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2)).press(forDuration: 0.1, thenDragTo: image.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.55)))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "iPad-image-occlusion-mask"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["occlusion-save"].tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: web)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 30), .completed, app.debugDescription)
        XCTAssertTrue(deck.waitForExistence(timeout: 30), app.debugDescription)
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in firstNumber(deck.label) == original + 1 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 20), .completed, deck.label)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

}
