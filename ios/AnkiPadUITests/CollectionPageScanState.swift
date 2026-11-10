import Foundation

/// Traverse towards the start once, then towards the end. A repeated
/// mounted-page identity marks a boundary; missing targets never mean success.
struct CollectionPageScanState {
    private var towardsStart = true
    private var previous: String?

    static func containsFullyMountedCell(_ frame: CGRect, in bounds: CGRect) -> Bool {
        frame.width > 0 && frame.height > 0 && frame.minY.isFinite && frame.maxY.isFinite && bounds.contains(frame)
    }

    mutating func nextDirection(after fingerprint: String) -> Bool? {
        if previous == fingerprint {
            guard towardsStart else { return nil }
            towardsStart = false
            previous = nil
        } else {
            previous = fingerprint
        }
        return towardsStart
    }
}
