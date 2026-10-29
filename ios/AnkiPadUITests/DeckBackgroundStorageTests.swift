import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers

final class DeckBackgroundStorageTests: StudyFlowTestSupport {
    @MainActor
    func testRejectedReplacementKeepsSavedBackgroundAndProfilesStayIndependent() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let first = base.appendingPathComponent("first"), second = base.appendingPathComponent("second")
        let store = DeckBackgroundStore()
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 24), format: format).image { context in
            context.cgContext.setFillColor(UIColor.red.cgColor); context.cgContext.fill(CGRect(x: 0, y: 0, width: 40, height: 24))
        }
        let png = try XCTUnwrap(image.pngData())
        try await store.save(.replace(png), root: first)
        let file = first.appendingPathComponent(DeckBackgroundStore.filename)
        let loaded = try await store.load(root: first)
        XCTAssertEqual(loaded?.cgImage?.width, 40); XCTAssertEqual(loaded?.cgImage?.height, 24)
        let absent = try await store.load(root: second); XCTAssertNil(absent)
        let sentinel = first.appendingPathComponent("collection.anki2")
        try Data("synthetic collection preservation marker".utf8).write(to: sentinel)
        do { try await store.save(.replace(Data("not an image".utf8)), root: first); XCTFail("Invalid image must be rejected") }
        catch { XCTAssertEqual(try Data(contentsOf: file), png) }
        do { try await store.save(.replace(Data(count: 10 * 1024 * 1024)), root: first); XCTFail("10MiB must be rejected") }
        catch is BoundedImageFile.TooLarge { XCTAssertEqual(try Data(contentsOf: file), png) }
        let largeFile = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "oversized-background", withExtension: "png"))
        do { _ = try await store.prepareFile(largeFile); XCTFail("Decoded bitmap exceeds 100MiB") }
        catch let error as DeckBackgroundError { XCTAssertTrue(error.message.contains("縦横サイズ")); XCTAssertEqual(try Data(contentsOf: file), png) }
        let jpeg = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let upright = try await store.prepare(jpeg as Data)
        XCTAssertEqual(upright.cgImage?.width, 24); XCTAssertEqual(upright.cgImage?.height, 40)
        try await store.save(.replace(jpeg as Data), root: second)
        try await store.save(.remove, root: first)
        let removed = try await store.load(root: first); XCTAssertNil(removed)
        XCTAssertEqual(try Data(contentsOf: second.appendingPathComponent(DeckBackgroundStore.filename)), jpeg as Data)
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "synthetic collection preservation marker")
        // The bounded file reader must reject before returning truncated data.
        do { _ = try BoundedImageFile.read(file.deletingLastPathComponent().appendingPathComponent("collection.anki2"), maximumBytes: 4); XCTFail("Oversized file must be rejected") }
        catch is BoundedImageFile.TooLarge {}
    }
}
