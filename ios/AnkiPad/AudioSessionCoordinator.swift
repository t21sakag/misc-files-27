import Foundation
#if os(iOS)
import AVFoundation
#endif

enum AudioSessionPurpose: Sendable { case playback, recording, recognition }

/// Cancellation is synchronous, including while native configuration is busy.
final class AudioSessionLease: @unchecked Sendable {
    let id: UUID
    private let lock = NSLock()
    private var valid = true
    private let revoked: @Sendable () -> Void
    init(id: UUID = UUID(), revoked: @escaping @Sendable () -> Void = {}) { self.id = id; self.revoked = revoked }
    var isValid: Bool { lock.lock(); defer { lock.unlock() }; return valid }
    func cancel() { lock.lock(); valid = false; lock.unlock() }
    fileprivate func revoke() {
        lock.lock(); let notify = valid; valid = false; lock.unlock()
        if notify { revoked() }
    }
}

/// A queued finalization completes even when its UI waiter is cancelled.
final class AudioFinalization<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Value?
    private var waiters: [CheckedContinuation<Value, Never>] = []
    func value() async -> Value {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let result { lock.unlock(); continuation.resume(returning: result) }
            else { waiters.append(continuation); lock.unlock() }
        }
    }
    fileprivate func complete(_ value: Value) {
        lock.lock(); result = value; let waiting = waiters; waiters.removeAll(); lock.unlock()
        waiting.forEach { $0.resume(returning: value) }
    }
}

/// One serial executor owns every native category/activation change. No caller
/// waits synchronously on the main thread, and an old owner cannot deactivate
/// a newer recording or playback session.
final class AudioSessionCoordinator: @unchecked Sendable {
    private let queue = DispatchQueue(label: "study.audio-session", qos: .userInitiated)
    private let configure: @Sendable (AudioSessionPurpose) throws -> Void
    private let deactivate: @Sendable () throws -> Void
    // Accessed exclusively by queue.
    private var purpose: AudioSessionPurpose?
    private var leases: [UUID: AudioSessionLease] = [:]

    init(configure: @escaping @Sendable (AudioSessionPurpose) throws -> Void,
         deactivate: @escaping @Sendable () throws -> Void) {
        self.configure = configure; self.deactivate = deactivate
    }

    func prepare(_ desired: AudioSessionPurpose, lease: AudioSessionLease) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.leases = self.leases.filter { $0.value.isValid }
                guard lease.isValid else { continuation.resume(throwing: CancellationError()); return }
                let previous = self.purpose
                do {
                    try self.configure(desired)
                    guard lease.isValid else { throw CancellationError() }
                    // Playback clients may coexist. Microphone clients and
                    // category changes replace incompatible owners explicitly.
                    for (id, old) in self.leases where id != lease.id {
                        if desired != .playback || previous != .playback { old.revoke() }
                    }
                    self.leases = self.leases.filter { $0.value.isValid }
                    self.leases[lease.id] = lease
                    self.purpose = desired
                    continuation.resume()
                } catch {
                    // A cancelled/failed setup can already have changed the
                    // category. Restore the prior live owner before processing
                    // the next queued request; never leave a stale setup last.
                    do {
                        if let previous, self.leases.values.contains(where: { $0.isValid }) {
                            try self.configure(previous)
                            self.purpose = previous
                        } else {
                            try self.deactivate(); self.purpose = nil
                        }
                    } catch {
                        self.leases.values.forEach { $0.revoke() }
                        self.leases.removeAll(); self.purpose = nil
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Player operations share the session executor, so a category switch
    /// cannot overtake a pending play or run concurrently with its stop.
    func perform<Value: Sendable>(lease: AudioSessionLease,
                                  _ operation: @escaping @Sendable () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
            queue.async {
                guard lease.isValid, self.leases[lease.id] != nil else {
                    continuation.resume(throwing: CancellationError()); return
                }
                do { continuation.resume(returning: try operation()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    /// Enqueue now, before release or a replacement can overtake file closure.
    func finalize<Value: Sendable>(_ operation: @escaping @Sendable () -> Value) -> AudioFinalization<Value> {
        let result = AudioFinalization<Value>()
        queue.async { result.complete(operation()) }
        return result
    }
    /// Cleanup refers to one player instance, even after its lease is cancelled.
    func cleanup(_ operation: @escaping @Sendable () -> Void) { queue.async(execute: operation) }

    func release(_ lease: AudioSessionLease, deactivate: Bool) {
        lease.cancel()
        queue.async {
            self.leases.removeValue(forKey: lease.id)
            self.leases = self.leases.filter { $0.value.isValid }
            guard deactivate, self.leases.isEmpty else { return }
            try? self.deactivate()
            self.purpose = nil
        }
    }

    #if os(iOS)
    static let shared = AudioSessionCoordinator(configure: { purpose in
        let session = AVAudioSession.sharedInstance()
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
        switch purpose {
        case .playback: category = .playback; mode = .default; options = []
        case .recording: category = .playAndRecord; mode = .default; options = [.defaultToSpeaker, .allowBluetooth]
        case .recognition: category = .record; mode = .measurement; options = [.duckOthers]
        }
        if session.category != category || session.mode != mode || session.categoryOptions != options {
            try session.setCategory(category, mode: mode, options: options)
        }
        try session.setActive(true)
    }, deactivate: {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    })
    #endif
}
