import Foundation

/// Retain nonempty fields that do not fit a newly selected note type. They
/// continue to block saving until the editor restores or explicitly clears them.
enum NewNoteFields {
    static func retaining(_ previous: [String], in buffer: [String]) -> [String] {
        var result = buffer
        for index in previous.indices {
            if result.indices.contains(index) { result[index] = previous[index] }
            else { result.append(previous[index]) }
        }
        return result
    }
    static func applying(_ buffer: [String], to defaults: [String]) -> [String] {
        defaults.enumerated().map { index, value in buffer.indices.contains(index) ? buffer[index] : value }
    }
    static func unmapped(_ buffer: [String], fieldCount: Int) -> [Int] {
        buffer.indices.filter { $0 >= fieldCount && !buffer[$0].isEmpty }
    }
}
