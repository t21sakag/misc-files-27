import Foundation
import ImageIO
import UIKit

/// Image editing/PNG conversion is optional. Animated, unsupported, and very
/// large images still attach as their original media files without rasterizing.
enum MediaImagePreparation {
    static let maximumEditableFileBytes = 32 * 1024 * 1024
    static let maximumEditableBitmapBytes: Int64 = 100 * 1024 * 1024
    static func canRasterize(_ url: URL) -> Bool {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maximumEditableFileBytes,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.int64Value,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.int64Value,
              width > 0, height > 0 else { return false }
        return width <= maximumEditableBitmapBytes / 4 / height
    }
    static func preview(_ url: URL) -> UIImage? {
        guard canRasterize(url), let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }
}
