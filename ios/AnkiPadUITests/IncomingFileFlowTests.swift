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
