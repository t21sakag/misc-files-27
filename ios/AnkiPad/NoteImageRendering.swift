import UIKit
import PencilKit

/// All edits operate on upright physical pixels, including EXIF-oriented photos.
enum NoteImageRendering {
    static func normalized(_ image: UIImage, drawing: PKDrawing = PKDrawing(), canvasSize: CGSize = .zero) -> UIImage {
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let bounds = CGRect(origin: .zero, size: size)
            image.draw(in: bounds)
            if !drawing.strokes.isEmpty, canvasSize.width > 0, canvasSize.height > 0 {
                drawing.image(from: CGRect(origin: .zero, size: canvasSize), scale: size.width / canvasSize.width).draw(in: bounds)
            }
        }
    }

    static func transformed(_ source: UIImage, rotate: Bool) -> UIImage {
        let size = rotate ? CGSize(width: source.size.height, height: source.size.width) : source.size
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            if rotate { context.cgContext.rotate(by: .pi / 2) }
            else { context.cgContext.scaleBy(x: -1, y: 1) }
            source.draw(in: CGRect(x: -source.size.width / 2, y: -source.size.height / 2, width: source.size.width, height: source.size.height))
        }
    }

    static func cropped(_ source: UIImage, unitRect: CGRect) -> UIImage? {
        let rect = CGRect(x: unitRect.minX * source.size.width, y: unitRect.minY * source.size.height,
                          width: unitRect.width * source.size.width, height: unitRect.height * source.size.height).integral
            .intersection(CGRect(origin: .zero, size: source.size))
        guard rect.width >= 1, rect.height >= 1, let result = source.cgImage?.cropping(to: rect) else { return nil }
        return UIImage(cgImage: result)
    }
}
