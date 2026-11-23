import Foundation
import StockfishCore

/// Drives the global C bridge for one session: start, send commands, collect output lines
/// until a predicate matches (or a timeout), then `sf_quit`.
enum BridgeHarness {
    struct Timeout: Error, CustomStringConvertible {
        let lines: [String]
        var description: String { "timed out; got \(lines.count) lines, last: \(lines.last ?? "-")" }
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
        timeout: Duration = .seconds(30)
    ) async throws -> [String] {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        let sink = Unmanaged.passRetained(Sink(continuation))
        defer { sink.release() }

        sf_start({ line, ctx in
            guard let line, let ctx else { return }
            Unmanaged<Sink>.fromOpaque(ctx).takeUnretainedValue().continuation.yield(String(cString: line))
        }, sink.toOpaque())
        defer {
            sf_quit()
            continuation.finish()
        }
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
        let lines = await collector.lines
        guard matched else { throw Timeout(lines: lines) }
        return lines
    }
}
