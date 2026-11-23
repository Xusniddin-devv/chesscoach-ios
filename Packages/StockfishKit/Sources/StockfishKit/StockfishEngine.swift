// The one Stockfish of the process, behind the C bridge.
//
// The bridge owns std::cin/std::cout globally, so there is exactly one engine:
// `StockfishEngine.shared`. Analysis and the bot opponent share it by switching options:
// `opponentMove` sets Skill Level / MultiPV 1, and every `analyze` sets Skill Level 20 and
// its MultiPV again before searching.
//
// Requests run one at a time in arrival order (an internal FIFO), so no command but the
// search itself is ever in flight: `setoption`, `position` and `go` are only sent once the
// previous `bestmove` has arrived (see the blocking rule in stockfish_bridge.h). Each search
// first sends the nets (Stockfish exits the process on `go` without them) and waits for
// `readyok`.
//
// Cancelling a caller never cuts an exchange short: it sends `stop` (allowed mid-search), the
// engine output is still read up to `bestmove`, and the caller gets `CancellationError`. The
// engine keeps running; only `EngineError`s restart it.

import ChessCore
import Foundation
import StockfishCore

public enum EngineError: Error {
    /// No `bestmove` (or `readyok`) within 30 s; the engine has been restarted.
    case timeout
    /// The engine stopped while a request waited for its output.
    case notRunning
}

public actor StockfishEngine: ChessEngine {
    public static let shared = StockfishEngine()

    private static let searchTimeout: Duration = .seconds(30)
    private static let output = OutputRouter()

    private var threads = 1
    private var hashMB = 64
    private var optionsChanged = true
    private var running = false

    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    private var cache = AnalysisCache()

    /// Number of `go` commands sent (test hook).
    private(set) var searchCount = 0
    /// The last `position` command sent (test hook).
    private(set) var lastPositionCommand: String?
    /// The `setoption` commands sent before the last search (test hook).
    private(set) var lastSearchOptions: [String] = []
    /// Number of engine starts (test hook).
    private(set) var startCount = 0

    private init() {}

    /// Threads and hash size, applied before the next search (never during one).
    public func configure(threads: Int, hashMB: Int) async {
        await acquire()
        defer { release() }
        self.threads = threads
        self.hashMB = hashMB
        optionsChanged = true
    }

#if DEBUG
    /// Measurement harness only: the threads and hash the next search will use.
    public var currentConfiguration: (threads: Int, hashMB: Int) { (threads, hashMB) }

    /// Measurement harness only: `go movetime` from the position, returning the deepest
    /// depth the search reached. Not cached.
    public func searchMovetime(startFen: String, moves: [String], multiPV: Int, milliseconds: Int) async throws -> Int {
        await acquire()
        defer { release() }
        let lines = try await search(
            startFen: startFen, moves: moves,
            options: ["Skill Level": "20", "MultiPV": "\(multiPV)"],
            go: "go movetime \(milliseconds)")
        return lines.compactMap(UCIParser.info).map(\.depth).max() ?? 0
    }

    /// Measurement harness only: forget the cached analysis so the next pass really searches.
    public func clearCache() async {
        await acquire()
        defer { release() }
        cache = AnalysisCache()
    }
#endif

    public func analyze(_ request: AnalysisRequest) async throws -> AnalysisResult {
        await acquire()
        defer { release() }
        if let cached = cache.get(request) { return cached }

        let lines = try await search(
            startFen: request.startFen, moves: request.moves,
            options: ["Skill Level": "20", "MultiPV": "\(request.multiPV)"],
            go: "go depth \(request.depth)")
        var deepest: [Int: PVLine] = [:]
        for line in lines.compactMap(UCIParser.info) where line.depth >= deepest[line.multipv]?.depth ?? 0 {
            deepest[line.multipv] = line
        }
        let result = AnalysisResult(
            bestMove: lines.last.flatMap(UCIParser.bestMove) ?? "",
            lines: deepest.values.sorted { $0.multipv < $1.multipv })
        cache.put(request, result)
        return result
    }

    public func opponentMove(startFen: String, moves: [String], elo: Int) async throws -> String {
        await acquire()
        defer { release() }
        let level = levelSettings(elo: elo)
        let lines = try await search(
            startFen: startFen, moves: moves,
            options: ["UCI_LimitStrength": "false", "Skill Level": "\(level.skillLevel)", "MultiPV": "1"],
            go: "go depth \(level.depth) movetime 2500")
        return lines.last.flatMap(UCIParser.bestMove) ?? ""
    }

    /// Quits the engine and starts a fresh one with its nets loaded. If the new start fails,
    /// the next request tries again.
    public func restart() async {
        await acquire()
        defer { release() }
        await restartNow()
    }

    /// Quits the engine; the next request starts it again. Tests use it to hand the bridge
    /// to a raw session.
    func shutdown() async {
        await acquire()
        defer { release() }
        stop()
    }

    // MARK: - FIFO

    private func acquire() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Hands the engine to the next waiting request, keeping `busy` set.
    private func release() {
        if waiting.isEmpty {
            busy = false
        } else {
            waiting.removeFirst().resume()
        }
    }

    // MARK: - Engine session (call only while holding the FIFO)

    private func search(startFen: String, moves: [String], options: KeyValuePairs<String, String>, go: String)
        async throws -> [String]
    {
        try Task.checkCancellation()
        do {
            try await startIfNeeded()
            var commands: [String] = []
            if optionsChanged {
                commands += ["setoption name Threads value \(threads)", "setoption name Hash value \(hashMB)"]
            }
            commands += Self.netCommands()
            commands += options.map { "setoption name \($0.key) value \($0.value)" }
            let position = moves.isEmpty
                ? "position fen \(startFen)"
                : "position fen \(startFen) moves \(moves.joined(separator: " "))"
            commands += [position, "isready"]
            _ = try await exchange(commands, until: { $0 == "readyok" })
            optionsChanged = false
            lastPositionCommand = position
            lastSearchOptions = commands.filter { $0.hasPrefix("setoption") }

            try Task.checkCancellation()
            searchCount += 1
            let output = try await exchange([go], until: { UCIParser.bestMove($0) != nil })
            try Task.checkCancellation()  // the move of a stopped search is not an answer
            return output
        } catch let error as EngineError {
            await restartNow()
            throw error
        }
    }

    private func startIfNeeded() async throws {
        guard !running else { return }
        let lines = Self.output.open()
        sf_start({ line, _ in
            guard let line else { return }
            StockfishEngine.output.route(String(cString: line))
        }, nil)
        running = true
        optionsChanged = true
        startCount += 1
        do {
            sf_send("uci")
            _ = try await Self.readToEnd(lines, until: { $0 == "uciok" })
            _ = try await exchange(Self.netCommands() + ["isready"], until: { $0 == "readyok" })
        } catch {
            stop()  // a half-started engine is quit, so the next request starts it again
            throw error
        }
    }

    /// Stockfish reloads a net only when its path changes, so resending these is cheap.
    private static func netCommands() -> [String] {
        let (big, small) = StockfishResources.netPaths()
        return ["setoption name EvalFile value \(big)", "setoption name EvalFileSmall value \(small)"]
    }

    private func restartNow() async {
        stop()
        try? await startIfNeeded()
    }

    private func stop() {
        guard running else { return }
        sf_quit()
        Self.output.close()
        running = false
        cache = AnalysisCache()
    }

    /// Sends `commands` and returns the output up to and including the line matching `done`.
    /// Cancellation sends `stop` and still waits for `done`.
    private func exchange(_ commands: [String], until done: @escaping @Sendable (String) -> Bool)
        async throws -> [String]
    {
        let lines = Self.output.open()
        return try await withTaskCancellationHandler {
            for command in commands { sf_send(command) }
            if Task.isCancelled { sf_send("stop") }  // cancelled before `go` was queued
            return try await Self.readToEnd(lines, until: done)
        } onCancel: {
            sf_send("stop")
        }
    }

    /// Reads in a task of its own, so the caller's cancellation cannot end it early.
    private static func readToEnd(_ lines: AsyncStream<String>, until done: @escaping @Sendable (String) -> Bool)
        async throws -> [String]
    {
        try await Task.detached { try await read(lines, until: done) }.value
    }

    private static func read(_ lines: AsyncStream<String>, until done: @escaping @Sendable (String) -> Bool)
        async throws -> [String]
    {
        try await withThrowingTaskGroup(of: [String]?.self) { group in
            group.addTask {
                var collected: [String] = []
                for await line in lines {
                    collected.append(line)
                    if done(line) { return collected }
                }
                throw EngineError.notRunning
            }
            group.addTask {
                // Suspending clock: time the app spends suspended does not count, so coming
                // back to the foreground mid-search does not look like a hung engine.
                try await Task.sleep(for: searchTimeout, tolerance: nil, clock: .suspending)
                return nil
            }
            defer { group.cancelAll() }
            guard let collected = try await group.next() ?? nil else { throw EngineError.timeout }
            return collected
        }
    }
}

/// Forwards engine output lines (delivered on engine threads) to the stream of the current
/// exchange. Opening a new stream finishes the previous one.
private final class OutputRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<String>.Continuation?

    func open() -> AsyncStream<String> {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        lock.withLock {
            self.continuation?.finish()
            self.continuation = continuation
        }
        return stream
    }

    func close() {
        lock.withLock {
            continuation?.finish()
            continuation = nil
        }
    }

    func route(_ line: String) {
        lock.withLock { _ = continuation?.yield(line) }
    }
}
