import Foundation

enum BoundedImageFile {
    struct TooLarge: LocalizedError {
        let maximumBytes: Int
        var errorDescription: String? { "画像ファイルは\(String(format: "%g", Double(maximumBytes + 1) / 1_048_576))MiB未満を選んでください。" }
    }
    static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        precondition(maximumBytes >= 0 && maximumBytes < Int.max)
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var data = Data()
        while data.count <= maximumBytes {
            let chunk = try file.read(upToCount: min(256 * 1024, maximumBytes + 1 - data.count)) ?? Data()
            if chunk.isEmpty { return data }
            data.append(chunk)
        }
        throw TooLarge(maximumBytes: maximumBytes)
    }
}
