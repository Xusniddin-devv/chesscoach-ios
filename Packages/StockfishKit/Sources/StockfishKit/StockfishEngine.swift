// The one Stockfish of the process, behind the C bridge.
//
// The bridge owns std::cin/std::cout globally, so there is exactly one engine:
// `StockfishEngine.shared`. Analysis and the bot opponent share it by switching options:
// `opponentMove` sets its strength options (see `botStyle`), and every analysis search sets
// UCI_LimitStrength false, Skill Level 20 and its MultiPV again before searching, so a bot's
// limit never leaks into a review.
//
// Requests run one at a time in arrival order (an internal FIFO), so no command but the
// search itself is ever in flight: `setoption`, `position` and `go` are only sent once the
// previous `bestmove` has arrived (see the blocking rule in stockfish_bridge.h). The nets are
// set once per engine start (Stockfish exits the process on `go` without them); resending
// `EvalFile` before every search cost ~0.3-0.7 s each (measured), so it isn't. Each search
// waits for `readyok` after its options.
//
// Cancelling a caller never cuts an exchange short: it sends `stop` (allowed mid-search), the
// engine output is still read up to `bestmove`, and the caller gets `CancellationError`. The
// engine keeps running; only `EngineError`s restart it.
//
// Background lane (`analyzeInBackground`, used by the app's analysis queue): foreground
// requests are served before waiting background ones, and a foreground request that arrives
// while a background search runs stops it at once (`stop`); the background caller gets
// `EngineYielded` and asks again later. So a foreground user waits for at most the few
// milliseconds a stopped search needs to print `bestmove`. Background results bypass the
// one-entry cache so they never evict the position a foreground screen is looking at.

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
    /// The nets were set on this engine run (setting `EvalFile` again costs a reload check of
    /// several hundred ms per search, so they go once per start).
    private var netsSent = false
    private var running = false

    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var backgroundWaiting: [CheckedContinuation<Void, Never>] = []
    /// The current holder came through the background lane.
    private var holderIsBackground = false
    /// A foreground request stopped the background holder's search.
    private var preempted = false

    private var cache = AnalysisCache()

    /// Number of `go` commands sent (test hook).
    private(set) var searchCount = 0
    /// The last `position` command sent (test hook).
    private(set) var lastPositionCommand: String?
    /// The last `go` command sent (test hook).
    private(set) var lastGoCommand: String?
    /// Background searches stopped by a foreground request (test hook).
    private(set) var preemptions = 0
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
            options: Self.analystOptions(multiPV: multiPV),
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
        let result = try await runAnalysis(request)
        cache.put(request, result)
        return result
    }

    /// Low priority: waits behind every foreground request and is stopped by one that arrives
    /// mid-search (`EngineYielded`). Not cached.
    public func analyzeInBackground(_ request: AnalysisRequest) async throws -> AnalysisResult {
        await acquire(background: true)
        defer { release() }
        if preempted { throw EngineYielded() }
        let result = try await runAnalysis(request)
        if preempted { throw EngineYielded() }  // a stopped search is not an answer
        return result
    }

    private func runAnalysis(_ request: AnalysisRequest) async throws -> AnalysisResult {
        let go = request.nodes.map { "go nodes \($0)" } ?? "go depth \(request.depth)"
        let lines = try await search(
            startFen: request.startFen, moves: request.moves,
            options: Self.analystOptions(multiPV: request.multiPV),
            go: go)
        return AnalysisResult(
            bestMove: lines.last.flatMap(UCIParser.bestMove) ?? "",
            lines: Self.deepestLines(lines))
    }

    private static func analystOptions(multiPV: Int) -> KeyValuePairs<String, String> {
        ["UCI_LimitStrength": "false", "Skill Level": "20", "MultiPV": "\(multiPV)"]
    }

    /// The deepest line reported for each MultiPV slot, in slot order.
    private static func deepestLines(_ output: [String]) -> [PVLine] {
        var deepest: [Int: PVLine] = [:]
        for line in output.compactMap(UCIParser.info) where line.depth >= deepest[line.multipv]?.depth ?? 0 {
            deepest[line.multipv] = line
        }
        return deepest.values.sorted { $0.multipv < $1.multipv }
    }

    public func opponentMove(startFen: String, moves: [String], elo: Int) async throws -> String {
        await acquire()
        defer { release() }
        switch botStyle(elo: elo) {
        case .full(let depth):
            let output = try await search(
                startFen: startFen, moves: moves,
                options: ["UCI_LimitStrength": "false", "Skill Level": "20", "MultiPV": "1"],
                go: "go depth \(depth) movetime 2500")
            return output.last.flatMap(UCIParser.bestMove) ?? ""
        case .limited(let uciElo, let movetimeMs):
            let output = try await search(
                startFen: startFen, moves: moves,
                options: ["UCI_LimitStrength": "true", "UCI_Elo": "\(uciElo)", "Skill Level": "20", "MultiPV": "1"],
                go: "go movetime \(movetimeMs)")
            return output.last.flatMap(UCIParser.bestMove) ?? ""
        case .humanlike(let style):
            let output = try await search(
                startFen: startFen, moves: moves,
                options: ["UCI_LimitStrength": "false", "Skill Level": "20", "MultiPV": "\(style.multiPV)"],
                go: "go depth \(style.depth) movetime 2500")
            let engineBest = output.last.flatMap(UCIParser.bestMove) ?? ""
            guard let fen = Rules.fen(startFen: startFen, moves: moves) else { return engineBest }
            let legal = Rules.legalMoves(fen: fen)
            guard !legal.isEmpty else { return engineBest }
            var rng = SystemRandomNumberGenerator()
            return pickHumanlikeMove(lines: Self.deepestLines(output), legalMoves: legal, style: style, using: &rng)
        }
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

    private func acquire(background: Bool = false) async {
        guard busy else {
            busy = true
            holderIsBackground = background
            preempted = false
            return
        }
        if background {
            await withCheckedContinuation { backgroundWaiting.append($0) }
        } else {
            if holderIsBackground && !preempted {
                // Stop the background search now; harmless if it hasn't sent `go` yet (it
                // checks `preempted` before searching).
                preempted = true
                preemptions += 1
                sf_send("stop")
            }
            await withCheckedContinuation { waiting.append($0) }
        }
    }

    /// Hands the engine to the next waiting request (foreground first), keeping `busy` set.
    private func release() {
        preempted = false
        if !waiting.isEmpty {
            holderIsBackground = false
            waiting.removeFirst().resume()
        } else if !backgroundWaiting.isEmpty {
            holderIsBackground = true
            backgroundWaiting.removeFirst().resume()
        } else {
            busy = false
            holderIsBackground = false
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
            if !netsSent { commands += Self.netCommands() }
            commands += options.map { "setoption name \($0.key) value \($0.value)" }
            let position = moves.isEmpty
                ? "position fen \(startFen)"
                : "position fen \(startFen) moves \(moves.joined(separator: " "))"
            commands += [position, "isready"]
            _ = try await exchange(commands, until: { $0 == "readyok" })
            optionsChanged = false
            netsSent = true
            lastPositionCommand = position
            lastSearchOptions = commands.filter { $0.hasPrefix("setoption") }

            try Task.checkCancellation()
            if holderIsBackground && preempted { throw EngineYielded() }
            searchCount += 1
            lastGoCommand = go
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
            netsSent = true
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
        netsSent = false
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
