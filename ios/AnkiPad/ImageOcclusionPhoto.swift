import Foundation
import UIKit

extension Engine {
    func prepareOcclusionPhoto(_ data: Data) throws -> URL {
        guard let image = UIImage(data: data) else { throw EngineError(message: "画像を読み込めませんでした。") }
        let editing = try preferences()["editing"] as? [String: Any] ?? [:]
        let png = editing["pasteImagesAsPng"] as? Bool ?? false
        let bytes: Data
        let ext: String
        if png {
            guard let encoded = image.pngData() else { throw EngineError(message: "画像を変換できませんでした。") }
            bytes = encoded; ext = "png"
        } else if data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) { bytes = data; ext = "png" }
        else if data.starts(with: [255, 216, 255]) { bytes = data; ext = "jpg" }
        else {
            guard let encoded = image.jpegData(compressionQuality: 0.95) else { throw EngineError(message: "画像を変換できませんでした。") }
            bytes = encoded; ext = "jpg"
        }
        let folder = root.appendingPathComponent("imports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let local = folder.appendingPathComponent("occlusion-" + UUID().uuidString + "." + ext)
        try bytes.write(to: local, options: .atomic)
        return local
    }
}
