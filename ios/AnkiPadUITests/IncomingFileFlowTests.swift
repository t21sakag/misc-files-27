import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers

final class IncomingFileFlowTests: StudyFlowTestSupport {
    private func temporaryFile(_ name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent(name)
    }
    private func image() -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 800), format: format).image { renderer in
            UIColor.red.setFill(); renderer.fill(CGRect(x: 0, y: 0, width: 1600, height: 800))
        }
    }
    private func animatedFile() throws -> URL {
        let url = try temporaryFile("incoming-animation.gif")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 2, nil)!
        let frame = image().cgImage!
        for _ in 0..<2 { CGImageDestinationAddImage(destination, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary) }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
    func testReceivedTextDocumentCancelPreservesOriginalAndCollection() throws {
        let file = try temporaryFile("incoming-cancel.csv")
        let bytes = Data("IncomingCSV sentinel,answer\n".utf8)
        try bytes.write(to: file)
        let app = makeApplication()
        app.launchArguments = []
        app.open(file)
        let cancel = app.buttons["incoming-import-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.staticTexts["incoming-cancel.csv"].exists)
        XCTAssertTrue(app.buttons["incoming-import-confirm"].exists)
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 20))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        assertBrowserContains(app, text: "IncomingCSV sentinel", exists: false)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testReceivedAnimatedImageAttachesOriginalAndPersistsOnNote() throws {
        let file = try animatedFile()
        let bytes = try Data(contentsOf: file)
        let app = makeApplication()
        app.launchArguments = []
        app.open(file)
        let attach = app.buttons["incoming-image-note"]
        XCTAssertTrue(attach.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.buttons["incoming-image-occlusion"].exists)
        attach.tap()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 30), app.debugDescription)
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", ".gif"), object: front)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 20), .completed, app.debugDescription)
        XCTAssertTrue((front.value as? String ?? "").contains("<img"))
        let insert = app.buttons["note-insert-received-media"]
        revealFormControl(insert, in: app.collectionViews["note-form"], topInset: 40, bottomInset: 20)
        XCTAssertTrue(insert.exists, app.debugDescription)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["note-close"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.buttons["deck-1"].waitForExistence(timeout: 30))
        app.buttons["deck-1"].tap()
        XCTAssertTrue(app.webViews.images.firstMatch.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testReceivedCollectionReplacementCanBeCancelledBeforeMutation() throws {
        let file = try temporaryFile("incoming-cancel.colpkg")
        let bytes = Data("Not parsed until final confirmation".utf8)
        try bytes.write(to: file)
        let app = makeApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["add-note"].waitForExistence(timeout: 30))
        addUnsyncedNote(app, frontText: "Keep existing collection sentinel")
        app.open(file)
        let replace = app.buttons["incoming-import-replace"]
        XCTAssertTrue(replace.waitForExistence(timeout: 30), app.debugDescription)
        replace.tap()
        let confirmation = app.buttons["incoming-import-replace-confirm"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10), app.debugDescription)
        let dialogCancel = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "キャンセル", "incoming-import-cancel")).firstMatch
        if dialogCancel.exists { dialogCancel.tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.15)).tap() }
        app.buttons["incoming-import-cancel"].tap()
        XCTAssertTrue(replace.waitForNonExistence(timeout: 20))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        assertBrowserContains(app, text: "Keep existing collection sentinel", exists: true)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testReceivedAudioAndVideoBecomeDraftAttachmentsWithoutSaving() throws {
        for (ext, marker) in [("wav", "[sound:"), ("mp4", "<video")] {
            let file = try temporaryFile("incoming-media." + ext)
            let bytes = Data("Synthetic attachment container".utf8)
            try bytes.write(to: file)
            let app = makeApplication()
            app.launchArguments = []
            app.open(file)
            let attach = app.buttons["incoming-media-note"]
            XCTAssertTrue(attach.waitForExistence(timeout: 30), app.debugDescription)
            attach.tap()
            let front = app.textViews["note-field-0"]
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND value CONTAINS %@", marker), object: front)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, app.debugDescription)
            XCTAssertTrue((front.value as? String ?? "").contains("." + ext))
            XCTAssertEqual(try Data(contentsOf: file), bytes)
            app.buttons["note-close"].tap(); app.buttons["破棄"].tap()
            assertBrowserContains(app, text: "incoming-media", exists: false)
            XCTAssertFalse(app.alerts.firstMatch.exists)
            app.terminate()
        }
    }
    func testReceivedStillImageOpensOcclusionAndSavesRealMask() throws {
        let file = try temporaryFile("incoming-mask.png")
        let bytes = image().pngData()!
        try bytes.write(to: file)
        let app = makeApplication()
        app.launchArguments = []
        app.open(file)
        let open = app.buttons["incoming-image-occlusion"]
        revealFormControl(open, in: app.collectionViews["incoming-import-form"], topInset: 40, bottomInset: 20)
        XCTAssertTrue(open.waitForExistence(timeout: 10), app.debugDescription)
        open.tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 30), app.debugDescription)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            web.images.allElementsBoundByIndex.contains { $0.frame.width > 100 && $0.frame.height > 100 }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 45), .completed, app.debugDescription)
        let canvas = try XCTUnwrap(web.images.allElementsBoundByIndex.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2)).press(forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.55)))
        app.buttons["occlusion-save"].tap()
        XCTAssertTrue(web.waitForNonExistence(timeout: 30), app.debugDescription)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        assertBrowserContains(app, text: "image-occlusion", exists: true)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testReceivedStillImageCanBeEditedSavedAndReopenedAsNoteMedia() throws {
        let file = try temporaryFile("incoming-still-note.png")
        let original = image().pngData()!
        try original.write(to: file)
        let app = makeApplication()
        app.launchArguments = []
        app.open(file)
        let attach = app.buttons["incoming-image-note"]
        revealFormControl(attach, in: app.collectionViews["incoming-import-form"], topInset: 40, bottomInset: 20)
        attach.tap()
        let editor = app.images["image-editor-image"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), app.debugDescription)
        func dimensions() -> [Int] {
            (editor.value as? String ?? "").components(separatedBy: "×").compactMap { Int($0.filter(\.isNumber)) }
        }
        XCTAssertEqual(dimensions(), [1600, 800])
        app.buttons["image-editor-rotate"].tap()
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            dimensions() == [800, 1600]
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
        // The editor owns the staged copy, including its original-data fallback.
        try FileManager.default.removeItem(at: file)
        app.buttons["image-editor-insert"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 30))
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20), app.debugDescription)
        let html = front.value as? String ?? ""
        XCTAssertTrue(html.contains("<img"), html)
        XCTAssertEqual(html.components(separatedBy: "<img").count - 1, 1)
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["note-close"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
        app.buttons["collection-menu"].tap(); app.buttons["browser-open"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-card-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), app.debugDescription); row.tap()
        XCTAssertTrue(front.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertEqual(front.value as? String, html)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testIncomingImagePreparationBoundsPreviewAndPreservesAnimation() throws {
        let still = try temporaryFile("still.png"), animated = try animatedFile()
        let original = image().pngData()!
        try original.write(to: still)
        XCTAssertTrue(MediaImagePreparation.canRasterize(still))
        let preview = try XCTUnwrap(MediaImagePreparation.preview(still)?.cgImage)
        XCTAssertLessThanOrEqual(max(preview.width, preview.height), 1024)
        XCTAssertGreaterThan(preview.width, 0)
        XCTAssertEqual(try Data(contentsOf: still), original)
        XCTAssertFalse(MediaImagePreparation.canRasterize(animated))
        XCTAssertNil(MediaImagePreparation.preview(animated))
        XCTAssertEqual(CGImageSourceGetCount(CGImageSourceCreateWithURL(animated as CFURL, nil)!), 2)
        let oversized = try temporaryFile("large.png")
        FileManager.default.createFile(atPath: oversized.path, contents: Data())
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(MediaImagePreparation.maximumEditableFileBytes + 1))
        try handle.close()
        XCTAssertFalse(MediaImagePreparation.canRasterize(oversized))
        XCTAssertNil(MediaImagePreparation.preview(oversized))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oversized.path))
    }
}
