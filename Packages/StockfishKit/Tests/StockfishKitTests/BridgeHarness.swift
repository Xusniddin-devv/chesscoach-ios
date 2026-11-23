import Foundation
import StockfishCore
@testable import StockfishKit

/// Drives the global C bridge for one session: start, send commands, collect output lines
/// until a predicate matches (or a timeout), send any follow-up commands, then `sf_quit`.
/// The shared `StockfishEngine` is shut down first so the session gets a fresh bridge; the
/// engine starts again on its next request.
enum BridgeHarness {
    struct Timeout: Error, CustomStringConvertible {
        let lines: [String]
        var description: String { "timed out; got \(lines.count) lines, last: \(lines.last ?? "-")" }
    }

    struct QuitTimeout: Error, CustomStringConvertible {
        var description: String { "sf_quit did not return in time" }
    }

    /// Ordered, thread-safe sink for engine lines (the callback runs on engine threads).
    private final class Sink: Sendable {
        let continuation: AsyncStream<String>.Continuation
        init(_ continuation: AsyncStream<String>.Continuation) { self.continuation = continuation }
    }

    /// Accumulates lines so a timeout can report what arrived.
    private actor Collector {
        private(set) var lines: [String] = []
        func append(_ line: String) { lines.append(line) }
    }

    static func run(
        _ commands: [String],
        until done: @escaping @Sendable (String) -> Bool,
        then followUp: [String] = [],
        timeout: Duration = .seconds(30),
        quitWithin quitTimeout: Duration = .seconds(10)
    ) async throws -> [String] {
        await StockfishEngine.shared.shutdown()
        let (stream, continuation) = AsyncStream<String>.makeStream()
        let sink = Unmanaged.passRetained(Sink(continuation))

        sf_start({ line, ctx in
            guard let line, let ctx else { return }
            Unmanaged<Sink>.fromOpaque(ctx).takeUnretainedValue().continuation.yield(String(cString: line))
        }, sink.toOpaque())
        for command in commands { sf_send(command) }

        let collector = Collector()
        let matched = try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await line in stream {
                    await collector.append(line)
                    if done(line) { return true }
                }
                return false
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return false
            }
            let first = try await group.next() ?? false
            group.cancelAll()
            return first
        }
        for command in followUp { sf_send(command) }

        // If quit hangs, the engine may still call back later, so the sink is leaked then.
        try await quit(within: quitTimeout)
        continuation.finish()
        sink.release()

        let lines = await collector.lines
        guard matched else { throw Timeout(lines: lines) }
        return lines
    }

    /// Runs `sf_quit` on its own thread so a hang fails the test instead of blocking it.
    private static func quit(within timeout: Duration) async throws {
        let once = Once()
        let returned: Bool = await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                sf_quit()
                once.run { continuation.resume(returning: true) }
            }
            Task {
                try? await Task.sleep(for: timeout)
                once.run { continuation.resume(returning: false) }
            }
        }
        guard returned else { throw QuitTimeout() }
    }

    /// Runs only the first closure handed to it.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func run(_ body: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            body()
        }
    }
}
