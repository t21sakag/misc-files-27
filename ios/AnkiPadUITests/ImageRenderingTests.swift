import XCTest
import UIKit
import PencilKit

final class ImageRenderingTests: XCTestCase {
    private func pixel(_ image: UIImage, x: Int, y: Int) -> [UInt8] {
        guard let point = image.cgImage?.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { XCTFail("Missing pixel"); return [] }
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(point, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Array(bytes.prefix(3))
    }
    private func fixture(scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: CGSize(width: 60, height: 40), format: format).image { context in
            for (color, rect) in [(UIColor.red, CGRect(x: 0, y: 0, width: 30, height: 20)),
                                  (UIColor.green, CGRect(x: 30, y: 0, width: 30, height: 20)),
                                  (UIColor.blue, CGRect(x: 0, y: 20, width: 30, height: 20)),
                                  (UIColor.yellow, CGRect(x: 30, y: 20, width: 30, height: 20))] {
                context.cgContext.setFillColor(color.cgColor); context.cgContext.fill(rect)
            }
        }
    }
    func testImageEditsPreserveExpectedPhysicalPixels() {
        let image = NoteImageRendering.normalized(fixture(scale: 2))
        XCTAssertEqual(image.cgImage?.width, 120); XCTAssertEqual(image.cgImage?.height, 80)
        let oriented = UIImage(cgImage: fixture().cgImage!, scale: 1, orientation: .right)
        let upright = NoteImageRendering.normalized(oriented)
        XCTAssertEqual(upright.cgImage?.width, 40); XCTAssertEqual(upright.cgImage?.height, 60)
        XCTAssertEqual(pixel(upright, x: 5, y: 5), [0, 0, 255])
        let rotated = NoteImageRendering.transformed(image, rotate: true)
        XCTAssertEqual(rotated.cgImage?.width, 80); XCTAssertEqual(rotated.cgImage?.height, 120)
        XCTAssertEqual(pixel(rotated, x: 10, y: 10), [0, 0, 255])
        XCTAssertEqual(pixel(rotated, x: 70, y: 10), [255, 0, 0])
        XCTAssertEqual(pixel(rotated, x: 10, y: 110), [255, 255, 0])
        let mirror = NoteImageRendering.transformed(image, rotate: false)
        XCTAssertEqual(pixel(mirror, x: 10, y: 10), [0, 255, 0])
        XCTAssertEqual(pixel(mirror, x: 110, y: 10), [255, 0, 0])
        let crop = NoteImageRendering.cropped(image, unitRect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))!
        XCTAssertEqual(crop.cgImage?.width, 60); XCTAssertEqual(crop.cgImage?.height, 40)
        XCTAssertEqual(pixel(crop, x: 30, y: 20), [255, 0, 0])
        XCTAssertNil(NoteImageRendering.cropped(image, unitRect: .zero))
        XCTAssertNil(NoteImageRendering.cropped(image, unitRect: CGRect(x: 2, y: 2, width: 1, height: 1)))
        // Actual encoding round trip must retain edited dimensions and pixels.
        let restored = UIImage(data: mirror.pngData()!)!
        XCTAssertEqual(restored.cgImage?.width, 120)
        XCTAssertEqual(pixel(restored, x: 10, y: 10), [0, 255, 0])
    }
    func testImageAnnotationIsCompositedAtCanvasScale() {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let white = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80), format: format).image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor); context.cgContext.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
        let points = [CGPoint(x: 5, y: 10), CGPoint(x: 25, y: 10)].enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: TimeInterval(index), size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        let drawing = PKDrawing(strokes: [stroke])
        let result = NoteImageRendering.normalized(white, drawing: drawing, canvasSize: CGSize(width: 30, height: 20))
        XCTAssertEqual(result.cgImage?.width, 120); XCTAssertEqual(result.cgImage?.height, 80)
        XCTAssertLessThan(pixel(result, x: 60, y: 40).map(Int.init).reduce(0, +), 300)
        XCTAssertEqual(pixel(result, x: 2, y: 2), [255, 255, 255])
    }
}
