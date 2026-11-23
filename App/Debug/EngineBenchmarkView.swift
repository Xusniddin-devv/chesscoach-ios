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
/// history; the engine's one-entry cache makes `before` of move N+1 free, as in the app.
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
    static let hashMB = 64
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

    /// Runs every configuration and restores threads 1 / hash 64 at the end, even on error.
    static func run(progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> [Row] {
        verifyMoves()
        let engine = StockfishEngine.shared
        var rows: [Row] = []
        do {
            for threads in threadCounts {
                progress("Threads \(threads): warming up")
                await engine.configure(threads: threads, hashMB: hashMB)
                await engine.clearCache()
                _ = try await gradePass(engine)  // discarded warm-up
                await engine.clearCache()
                progress("Threads \(threads): timing")
                let ms = try await gradePass(engine)
                let reached = try await engine.searchMovetime(
                    startFen: Rules.startFen, moves: Array(moves.prefix(moves.count / 2)),
                    multiPV: multiPV, milliseconds: movetimeMs)
                rows.append(Row(threads: threads, msPerGradedMove: ms, movetimeDepth: reached))
            }
        } catch {
            await engine.configure(threads: 1, hashMB: hashMB)
            throw error
        }
        await engine.configure(threads: 1, hashMB: hashMB)
        return rows
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

    /// Headless entry (`-engineBenchmark` launch argument): writes Documents/engine-benchmark.md.
    static func runHeadless() async {
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
        .onDisappear { Task { await StockfishEngine.shared.configure(threads: 1, hashMB: EngineBenchmark.hashMB) } }
    }

    private func start() {
        running = true
        rows = []
        Task {
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

/// The Profile tab's placeholder plus the debug-only way into the benchmark.
struct DebugProfilePlaceholder: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                ComingSoonView(title: "Profile")
                NavigationLink("Engine benchmark (debug)") { EngineBenchmarkView() }
                    .padding(DS.Spacing.m)
            }
            .background(DS.Color.background)
        }
    }
}
#endif
