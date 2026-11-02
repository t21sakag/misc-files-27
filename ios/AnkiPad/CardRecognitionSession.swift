import Foundation

/// Stopping input during permission/session setup must not start a microphone
/// later. Once listening, stop retains the token for the final recognition.
struct CardRecognitionSession {
    private enum Phase { case idle, preparing, listening, finishing }
    private var phase = Phase.idle
    private var token: UUID?
    mutating func begin() -> UUID {
        let next = UUID(); token = next; phase = .preparing; return next
    }
    func isCurrent(_ value: UUID) -> Bool { token == value }
    func canStart(_ value: UUID) -> Bool { token == value && phase == .preparing }
    @discardableResult mutating func didStart(_ value: UUID) -> Bool {
        guard canStart(value) else { return false }
        phase = .listening; return true
    }
    mutating func stopInput() {
        switch phase {
        case .preparing: cancel()
        case .listening: phase = .finishing
        case .idle, .finishing: break
        }
    }
    mutating func cancel() { token = nil; phase = .idle }
}
