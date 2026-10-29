import Foundation
import UIKit
import ImageIO

struct DeckBackgroundError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum DeckBackgroundChange {
    case unchanged, remove, replace(Data)
}

/// The file belongs to the collection's profile root, outside collection.media.
/// Validation precedes atomic replacement so a failed import keeps the old image.
actor DeckBackgroundStore {
    static let shared = DeckBackgroundStore()
    static let maximumFileBytes = 10 * 1024 * 1024 - 1
    static let maximumBitmapBytes = 100 * 1024 * 1024
    static let filename = "DeckPickerBackground.png"

    func prepare(_ data: Data) throws -> UIImage {
        guard data.count <= Self.maximumFileBytes else { throw BoundedImageFile.TooLarge(maximumBytes: Self.maximumFileBytes) }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.int64Value,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.int64Value,
              width > 0, height > 0 else { throw DeckBackgroundError(message: "画像を読み込めませんでした。") }
        // Divide before multiplying; dimensions from an untrusted header may overflow.
        guard width <= Int64(Self.maximumBitmapBytes) / 4 / height else {
            throw DeckBackgroundError(message: "画像の縦横サイズが大きすぎます（展開後100MiB以下）。")
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceCreateThumbnailWithTransform: true,
                                      kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                                      kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw DeckBackgroundError(message: "画像を読み込めませんでした。")
        }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }
    func prepareFile(_ url: URL) throws -> (Data, UIImage) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try BoundedImageFile.read(url, maximumBytes: Self.maximumFileBytes)
        return (data, try prepare(data))
    }
    func load(root: URL) throws -> UIImage? {
        let file = root.appendingPathComponent(Self.filename)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try prepare(BoundedImageFile.read(file, maximumBytes: Self.maximumFileBytes))
    }
    func save(_ change: DeckBackgroundChange, root: URL) throws {
        let file = root.appendingPathComponent(Self.filename)
        switch change {
        case .unchanged: return
        case .remove:
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        case .replace(let data):
            _ = try prepare(data)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        }
    }
}
