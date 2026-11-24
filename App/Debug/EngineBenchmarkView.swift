#if DEBUG
import SwiftUI
import ChessCore
import StockfishKit

/// Measures the real access pattern (warm engine, sequential related positions, many short
/// searches) per engine configuration. Debug builds only; reached from the Profile tab
/// (a long-press on a system tab item is not available) or headless via `-engineBenchmark`.
///
/// Per configuration: one discarded warm-up pass, then a timed pass over 20 graded moves.
/// A graded move is `analyze(before)` + `analyze(after)` at depth 16, MultiPV 2, with full
/// history; the engine's one-entry cache makes `before` of move N+1 free, so a graded move
/// costs one search. The app grades only the user's moves; it gets the same one-search wait
/// because `GameSession` prefetches the next `before` while the user thinks.
/// The cache is cleared before each pass so the pass really searches. Then `go movetime 300`
/// from the middle position reports the depth reached.
///
/// Net choice is not measured: Stockfish 18 cannot run with the small net as `EvalFile` (the
/// big net has another architecture, the file fails to load and the engine exits), so
/// small-only needs an engine patch. See docs/reference/engine-measurements.md.
enum EngineBenchmark {
    /// Ruy Lopez, Chigorin, first 20 plies from the start position.
    static let moves = [
        "e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6", "b5a4", "g8f6", "e1g1", "f8e7",
        "f1e1", "b7b5", "a4b3", "d7d6", "c2c3", "e8g8", "h2h3", "c6a5", "b3c2", "c7c5",
    ]
    static let threadCounts = [1, 2, 4]
    static let depth = 16
    static let multiPV = 2
    static let movetimeMs = 300

    struct Row: Identifiable, Sendable {
        let threads: Int
        let msPerGradedMove: Int
        let movetimeDepth: Int
        var id: Int { threads }
    }

    /// Fails loudly if any move is illegal.
    static func verifyMoves() {
        var fen = Rules.startFen
        for (ply, uci) in moves.enumerated() {
            guard let applied = Rules.apply(uci: uci, to: fen) else {
                preconditionFailure("benchmark move \(ply + 1) \(uci) is illegal in \(fen)")
            }
            fen = applied.fenAfter
        }
    }

    /// Runs every configuration; the app's default threads / hash are restored on every exit
    /// path (finish, error, cancellation).
    static func run(threadCounts: [Int] = EngineBenchmark.threadCounts, progress: @escaping @Sendable (String) -> Void = { _ in })
        async throws -> [Row]
    {
        verifyMoves()
        let engine = StockfishEngine.shared
        var rows: [Row] = []
        do {
            for threads in threadCounts {
                try Task.checkCancellation()
                progress("Threads \(threads): warming up")
                await engine.configure(threads: threads, hashMB: EngineHub.defaultHashMB)
                await engine.clearCache()
                _ = try await gradePass(engine)  // discarded warm-up
                try Task.checkCancellation()
                await engine.clearCache()
                progress("Threads \(threads): timing")
                let ms = try await gradePass(engine)
                let reached = try await engine.searchMovetime(
                    startFen: Rules.startFen, moves: Array(moves.prefix(moves.count / 2)),
                    multiPV: multiPV, milliseconds: movetimeMs)
                rows.append(Row(threads: threads, msPerGradedMove: ms, movetimeDepth: reached))
            }
        } catch {
            await restoreDefaults(engine)
            throw error
        }
        await restoreDefaults(engine)
        return rows
    }

    private static func restoreDefaults(_ engine: StockfishEngine) async {
        await engine.configure(threads: EngineHub.defaultThreads, hashMB: EngineHub.defaultHashMB)
    }

    /// Average ms per graded move over the 20 moves.
    private static func gradePass(_ engine: StockfishEngine) async throws -> Int {
        let clock = ContinuousClock()
        let start = clock.now
        for n in 0..<moves.count {
            for count in [n, n + 1] {
                _ = try await engine.analyze(AnalysisRequest(
                    startFen: Rules.startFen, moves: Array(moves.prefix(count)), depth: depth, multiPV: multiPV))
            }
        }
        let elapsed = clock.now - start
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        return Int((ms / Double(moves.count)).rounded())
    }

    static func markdown(_ rows: [Row]) -> String {
        var out = "| Threads | Nets | Avg ms per graded move (depth \(depth), MultiPV \(multiPV)) | Depth in go movetime \(movetimeMs) |\n"
        out += "| --- | --- | --- | --- |\n"
        for r in rows { out += "| \(r.threads) | big+small | \(r.msPerGradedMove) | \(r.movetimeDepth) |\n" }
        return out
    }

    /// Quick-pass calibration: ms per position for node-limited searches (MultiPV 1, the
    /// onboarding quick pass) per thread count, over the benchmark game's positions.
    static func quickPass(nodes: [Int] = [10_000, 20_000, 30_000, 50_000, 80_000],
                          threadCounts: [Int] = [1, 4]) async throws -> String {
        verifyMoves()
        let engine = StockfishEngine.shared
        var out = "| Threads | Nodes | ms per position (avg) | max ms |\n| --- | --- | --- | --- |\n"
        let clock = ContinuousClock()
        for threads in threadCounts {
            await engine.configure(threads: threads, hashMB: EngineHub.defaultHashMB)
            // Warm-up.
            for n in 0..<4 {
                _ = try await engine.analyze(AnalysisRequest(startFen: Rules.startFen, moves: Array(moves.prefix(n)),
                                                             depth: 0, multiPV: 1, nodes: 20_000))
            }
            for limit in nodes {
                var total = Duration.zero
                var worst = Duration.zero
                for n in 0...moves.count {
                    let start = clock.now
                    _ = try await engine.analyzeInBackground(AnalysisRequest(
                        startFen: Rules.startFen, moves: Array(moves.prefix(n)), depth: 0, multiPV: 1, nodes: limit))
                    let took = clock.now - start
                    total += took
                    worst = max(worst, took)
                }
                let avg = total / (moves.count + 1)
                func ms(_ d: Duration) -> String { String(format: "%.1f", Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000) }
                out += "| \(threads) | \(limit) | \(ms(avg)) | \(ms(worst)) |\n"
            }
        }
        await restoreDefaults(engine)
        return out
    }

    /// Headless entry (`-engineBenchmark` launch argument): writes Documents/engine-benchmark.md.
    /// `-engineBenchmark quick` writes Documents/quick-benchmark.md instead.
    static func runHeadless() async {
        if UserDefaults.standard.string(forKey: "engineBenchmark") == "quick" {
            let url = URL.documentsDirectory.appending(path: "quick-benchmark.md")
            do {
                try await quickPass().write(to: url, atomically: true, encoding: .utf8)
            } catch {
                try? "failed: \(error)\n".write(to: url, atomically: true, encoding: .utf8)
            }
            return
        }
        let url = URL.documentsDirectory.appending(path: "engine-benchmark.md")
        do {
            let rows = try await run()
            try markdown(rows).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            try? "failed: \(error)\n".write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct EngineBenchmarkView: View {
    @State private var rows: [EngineBenchmark.Row] = []
    @State private var status = "Not run"
    @State private var running = false
    @State private var runTask: Task<Void, Never>?

    var body: some View {
        List {
            Section {
                Button(running ? "Running" : "Run benchmark") { start() }.disabled(running)
                Text(status).foregroundStyle(DS.Color.textSecondary)
            }
            Section("Results (big+small nets)") {
                ForEach(rows) { r in
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("Threads \(r.threads)").foregroundStyle(DS.Color.text)
                        Text("\(r.msPerGradedMove) ms per graded move, depth \(r.movetimeDepth) in movetime \(EngineBenchmark.movetimeMs)")
                            .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                    }
                }
            }
            if !rows.isEmpty {
                Button("Copy as Markdown") { UIPasteboard.general.string = EngineBenchmark.markdown(rows) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(DS.Color.background)
        .navigationTitle("Engine benchmark")
        .onDisappear { runTask?.cancel() }  // run() restores the defaults itself
    }

    private func start() {
        running = true
        rows = []
        runTask = Task {
            do {
                rows = try await EngineBenchmark.run { message in Task { @MainActor in status = message } }
                status = "Done"
            } catch {
                status = "Failed: \(error)"
            }
            running = false
        }
    }
}

#endif
