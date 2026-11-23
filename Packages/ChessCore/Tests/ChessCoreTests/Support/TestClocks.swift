import Foundation

struct TestInstant: InstantProtocol {
    var offset: Duration

    func advanced(by duration: Duration) -> TestInstant { TestInstant(offset: offset + duration) }
    func duration(to other: TestInstant) -> Duration { other.offset - offset }
    static func < (lhs: TestInstant, rhs: TestInstant) -> Bool { lhs.offset < rhs.offset }
}

/// A clock whose sleeps finish at once (time jumps to the deadline).
final class ImmediateClock: _Concurrency.Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current = TestInstant(offset: .zero)

    var now: TestInstant { lock.withLock { current } }
    var minimumResolution: Duration { .zero }

    func sleep(until deadline: TestInstant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        lock.withLock { current = max(current, deadline) }
    }
}

/// A clock that only moves when the test calls `advance(by:)`. Sleeps honour cancellation.
final class ManualClock: _Concurrency.Clock, @unchecked Sendable {
    private struct Sleeper {
        var deadline: TestInstant
        var continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var current = TestInstant(offset: .zero)
    private var sleepers: [UUID: Sleeper] = [:]
    private var cancelled: Set<UUID> = []
    private var _sleepDurations: [Duration] = []

    var now: TestInstant { lock.withLock { current } }
    var minimumResolution: Duration { .zero }
    var sleeperCount: Int { lock.withLock { sleepers.count } }
    /// Requested sleep lengths, measured from `now` at the time of the call.
    var sleepDurations: [Duration] { lock.withLock { _sleepDurations } }

    func sleep(until deadline: TestInstant, tolerance: Duration?) async throws {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                let resumeNow = lock.withLock { () -> Bool in
                    _sleepDurations.append(current.duration(to: deadline))
                    if deadline <= current || cancelled.contains(id) { return true }
                    sleepers[id] = Sleeper(deadline: deadline, continuation: c)
                    return false
                }
                if resumeNow { c.resume() }
            }
        } onCancel: {
            let c = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                if let s = sleepers.removeValue(forKey: id) { return s.continuation }
                cancelled.insert(id)
                return nil
            }
            c?.resume()
        }
        try Task.checkCancellation()
    }

    func advance(by duration: Duration) {
        let due = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            current = current.advanced(by: duration)
            let ready = sleepers.filter { $0.value.deadline <= current }
            ready.keys.forEach { sleepers.removeValue(forKey: $0) }
            return ready.values.map(\.continuation)
        }
        due.forEach { $0.resume() }
    }
}
