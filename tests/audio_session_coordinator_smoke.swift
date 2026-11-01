import Foundation

private enum ProbeError: Error { case configuration }
private final class Probe: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    private var blocked: AudioSessionPurpose?
    private var entered = false
    private var fail: AudioSessionPurpose?
    private let gate = DispatchSemaphore(value: 0)
    var events: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    var isBlocked: Bool { lock.lock(); defer { lock.unlock() }; return entered }
    func block(_ purpose: AudioSessionPurpose) { lock.lock(); blocked = purpose; entered = false; lock.unlock() }
    func unblock() { gate.signal() }
    func failOnce(_ purpose: AudioSessionPurpose) { lock.lock(); fail = purpose; lock.unlock() }
    func configure(_ purpose: AudioSessionPurpose) throws {
        precondition(!Thread.isMainThread, "Native session configuration blocked the main thread")
        lock.lock()
        storage.append(String(describing: purpose))
        let shouldBlock = blocked == purpose
        if shouldBlock { blocked = nil; entered = true }
        let shouldFail = fail == purpose
        if shouldFail { fail = nil }
        lock.unlock()
        if shouldBlock { precondition(gate.wait(timeout: .now() + 5) == .success) }
        if shouldFail { throw ProbeError.configuration }
    }
    func revoked(_ owner: String) { lock.lock(); storage.append("revoked." + owner); lock.unlock() }
    func deactivate() {
        precondition(!Thread.isMainThread, "Native deactivation blocked the main thread")
        lock.lock(); storage.append("deactivate"); lock.unlock()
    }
}

@main struct AudioSessionCoordinatorSmoke {
    static func barrier(_ coordinator: AudioSessionCoordinator) async {
        let lease = AudioSessionLease(); lease.cancel()
        do { try await coordinator.prepare(.playback, lease: lease); preconditionFailure("Cancelled setup succeeded") }
        catch is CancellationError {} catch { preconditionFailure("Unexpected error: \(error)") }
    }
    static func main() async throws {
        let probe = Probe()
        let coordinator = AudioSessionCoordinator(configure: { try probe.configure($0) }, deactivate: { probe.deactivate() })
        let first = AudioSessionLease()
        let second = AudioSessionLease { probe.revoked("playback") }
        try await coordinator.prepare(.playback, lease: first)
        try await coordinator.prepare(.playback, lease: second)
        precondition(first.isValid && second.isValid, "Compatible playback clients must coexist")
        coordinator.release(first, deactivate: true)
        await barrier(coordinator)
        precondition(!probe.events.contains("deactivate"), "One owner stopped another owner's playback")

        let recording = AudioSessionLease { probe.revoked("recording") }
        try await coordinator.prepare(.recording, lease: recording)
        precondition(!second.isValid && recording.isValid, "Recording must revoke incompatible playback")
        coordinator.release(second, deactivate: true)
        await barrier(coordinator)
        precondition(!probe.events.contains("deactivate"), "An old playback owner deactivated recording")

        probe.block(.recognition)
        let cancelled = AudioSessionLease()
        let pending = Task { try await coordinator.prepare(.recognition, lease: cancelled) }
        for _ in 0..<200 {
            if probe.isBlocked { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        precondition(probe.isBlocked)
        cancelled.cancel()
        probe.unblock()
        do { try await pending.value; preconditionFailure("Cancelled native setup succeeded") }
        catch is CancellationError {} catch { preconditionFailure("Unexpected error: \(error)") }
        precondition(recording.isValid, "A cancelled setup revoked the prior recording")
        precondition(probe.events.suffix(2) == ["recognition", "recording"], "Cancelled category was left active")

        probe.failOnce(.playback)
        let failed = AudioSessionLease()
        do { try await coordinator.prepare(.playback, lease: failed); preconditionFailure("Native failure ignored") }
        catch ProbeError.configuration {} catch { preconditionFailure("Unexpected error: \(error)") }
        precondition(recording.isValid && probe.events.last == "recording", "Failed setup did not restore prior owner")
        coordinator.release(failed, deactivate: true)
        await barrier(coordinator)
        precondition(!probe.events.contains("deactivate"), "Failed request deactivated the restored owner")

        let replacement = AudioSessionLease()
        try await coordinator.prepare(.recording, lease: replacement)
        precondition(!recording.isValid && replacement.isValid)
        coordinator.release(recording, deactivate: true)
        await barrier(coordinator)
        precondition(!probe.events.contains("deactivate"), "Old microphone cleanup stopped its replacement")
        coordinator.release(replacement, deactivate: true)
        await barrier(coordinator)
        precondition(probe.events.filter { $0 == "deactivate" }.count == 1)
        precondition(probe.events.filter { $0 == "revoked.playback" }.count == 1)
        precondition(probe.events.filter { $0 == "revoked.recording" }.count == 1)
        let count = probe.events.count
        let neverStarted = AudioSessionLease(); neverStarted.cancel()
        do { try await coordinator.prepare(.playback, lease: neverStarted); preconditionFailure("Cancelled request started") }
        catch is CancellationError {} catch { preconditionFailure("Unexpected error") }
        precondition(probe.events.count == count)
        let operationLease = AudioSessionLease()
        try await coordinator.prepare(.playback, lease: operationLease)
        let value = try await coordinator.perform(lease: operationLease) {
            precondition(!Thread.isMainThread)
            return 17
        }
        precondition(value == 17)
        coordinator.release(operationLease, deactivate: false)
        do {
            _ = try await coordinator.perform(lease: operationLease) { () -> Int in preconditionFailure("Cancelled player operation executed") }
            preconditionFailure("Cancelled player operation succeeded")
        } catch is CancellationError {} catch { preconditionFailure("Unexpected player error") }
        coordinator.cleanup { probe.revoked("cleanup") }
        await barrier(coordinator)
        precondition(probe.events.last == "revoked.cleanup", "Cancelled player cleanup was lost")
        print("PASS: audio configuration/deactivation run off main; shared playback, cancelled/failed category rollback, incompatible replacement and old-owner cleanup preserve the live session")
    }
}
