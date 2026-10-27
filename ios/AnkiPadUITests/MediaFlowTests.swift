import XCTest

final class MediaFlowTests: StudyFlowTestSupport {
    func testPhotoEditsAndDrawingPersistWhenReeditingNote() {
        let app = makeApplication()
        app.launch()
        XCTAssertTrue(app.buttons["add-note"].waitForExistence(timeout: 30))
        app.buttons["add-note"].tap()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20))
        front.tap(); front.typeText("Image editing verification")
        let attach = app.buttons["note-attachment-0"]
        func openAttachment() {
            let hideKeyboard = app.buttons["Hide keyboard"]
            if hideKeyboard.exists && hideKeyboard.isHittable { hideKeyboard.tap() }
            let form = app.collectionViews["note-form"]
            for _ in 0..<10 {
                let viewport = form.frame.insetBy(dx: 0, dy: 72)
                if attach.exists && attach.isHittable && viewport.contains(attach.frame) { break }
                let below = !attach.exists || attach.frame.midY > form.frame.midY
                // A full swipe can overshoot this short row. Controlled drag,
                // release at rest, and scroll back down when it is above us.
                form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).press(forDuration: 0.05,
                    thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.32 : 0.78)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
            }
            waitUntilHittable(attach)
            XCTAssertTrue(form.frame.insetBy(dx: 0, dy: 72).contains(attach.frame), app.debugDescription)
            attach.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        openAttachment()
        let choosePhoto = app.buttons["note-photo-0"].firstMatch
        XCTAssertTrue(choosePhoto.waitForExistence(timeout: 20), app.debugDescription)
        choosePhoto.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 30), app.debugDescription)
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let image = app.images["image-editor-image"]
        XCTAssertTrue(image.waitForExistence(timeout: 30), app.debugDescription)
        func dimensions() -> [Int] {
            (image.value as? String ?? "").components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
        }
        XCTAssertEqual(dimensions(), [512, 384])
        app.buttons["image-editor-rotate"].tap()
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in image.exists && dimensions() == [384, 512] }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 20), .completed)
        app.buttons["image-editor-mirror"].tap()
        XCTAssertEqual(dimensions(), [384, 512])
        image.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.2)).press(forDuration: 0.1,
            thenDragTo: image.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.7)))
        let crop = app.buttons["image-editor-crop"]
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: crop)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 20), .completed)
        crop.tap()
        let cropped = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let size = dimensions(); return size.count == 2 && size[0] > 10 && size[0] < 384 && size[1] > 10 && size[1] < 512
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [cropped], timeout: 20), .completed)
        let savedSize = dimensions()
        let drawing = app.switches["image-editor-drawing"]
        func setDrawing(_ enabled: Bool) {
            let desired = enabled ? "1" : "0"
            if drawing.value as? String != desired {
                let native = drawing.switches.firstMatch
                if native.exists { native.tap() }
                else { drawing.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
            }
            let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", desired), object: drawing)
            XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 10), .completed, app.debugDescription)
        }
        setDrawing(true)
        let canvas = app.descendants(matching: .any).matching(identifier: "whiteboard").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 20), app.debugDescription)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)))
        let ink = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard canvas.exists, let value = canvas.value as? String else { return false }
            return (value.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init).first ?? 0) > 0
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ink], timeout: 20), .completed, app.debugDescription)
        setDrawing(false)
        app.buttons["image-editor-insert"].tap()
        XCTAssertTrue(image.waitForNonExistence(timeout: 30))
        XCTAssertTrue(front.waitForExistence(timeout: 20))
        let firstHTML = front.value as? String ?? ""
        XCTAssertEqual(firstHTML.components(separatedBy: "<img ").count - 1, 1)
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30))
        app.buttons["note-close"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
        app.buttons["collection-menu"].tap(); app.buttons["browser-open"].tap()
        let search = app.searchFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", "検索（")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap(); search.typeText("Image editing verification")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'browser-card-' AND label CONTAINS 'Image editing verification'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20)); row.tap()
        XCTAssertTrue(front.waitForExistence(timeout: 20))
        XCTAssertEqual(front.value as? String, firstHTML)
        openAttachment()
        let editImage = app.buttons["note-edit-image-0"].firstMatch
        XCTAssertTrue(editImage.waitForExistence(timeout: 20), app.debugDescription)
        editImage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let existing = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'field-image-'")).firstMatch
        XCTAssertTrue(existing.waitForExistence(timeout: 20)); existing.tap()
        XCTAssertTrue(image.waitForExistence(timeout: 30))
        XCTAssertEqual(dimensions(), savedSize, "Read the saved media file, not a retained draft image")
        app.buttons["image-editor-mirror"].tap()
        app.buttons["image-editor-insert"].tap()
        XCTAssertTrue(image.waitForNonExistence(timeout: 30))
        let replacement = front.value as? String ?? ""
        XCTAssertTrue(replacement.hasPrefix("Image editing verification"))
        XCTAssertNotEqual(replacement, firstHTML, "Existing image source must be replaced with the new media file")
        XCTAssertEqual(replacement.components(separatedBy: "<img ").count - 1, 1, "Editing must not append a second image")
        app.buttons["note-save"].tap()
        XCTAssertTrue(front.waitForNonExistence(timeout: 30))
        XCTAssertTrue(row.waitForExistence(timeout: 20)); row.tap()
        XCTAssertTrue(front.waitForExistence(timeout: 20))
        XCTAssertEqual(front.value as? String, replacement, "The replacement must persist in the existing note")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

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
