import Foundation
import Observation

/// Grades the moves of one line (a Review branch) one at a time, in the order they were
/// played, each from its own history. Same semantics as `GameSession`'s grading queue:
/// every job carries its own snapshot, results from an older generation are dropped, and a
/// `CancellationError` is not an engine failure.
///
/// Plies are 1-based from `startFen`: the move played after `history` is ply `history.count + 1`.
@MainActor @Observable
public final class LineGrader {
    public let startFen: String
    public let depth: Int

    /// Finished grades, keyed by ply.
    public private(set) var verdicts: [Int: Verdict] = [:]
    /// Grades queued or running.
    public private(set) var pendingCount = 0
    /// An engine call failed; the queue waits for `retry()`.
    public private(set) var hasError = false

    private struct Job: Sendable {
        var fenBefore: String
        var fenAfter: String
        var historyBefore: [String]
        var uci: String
        var san: String
        var mover: Piece.Color
        var ply: Int
        var generation: Int
    }

    @ObservationIgnored private let engine: any ChessEngine
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var queue: [Job] = [] {
        didSet { pendingCount = queue.count }
    }
    @ObservationIgnored private var drainTask: Task<Void, Never>?

    public init(engine: any ChessEngine, startFen: String = Rules.startFen, depth: Int = 14) {
        self.engine = engine
        self.startFen = startFen
        self.depth = depth
    }

    /// Queues the grade of `uci` played after `history`. Returns false (nothing queued) when
    /// the history or the move is illegal.
    @discardableResult
    public func enqueue(history: [String], uci: String) -> Bool {
        var fen = startFen
        for move in history {
            guard let applied = Rules.apply(uci: move, to: fen) else { return false }
            fen = applied.fenAfter
        }
        guard let applied = Rules.apply(uci: uci, to: fen) else { return false }
        let mover: Piece.Color = fen.split(separator: " ").dropFirst().first == "b" ? .black : .white
        queue.append(Job(fenBefore: fen, fenAfter: applied.fenAfter, historyBefore: history, uci: uci,
                         san: applied.san, mover: mover, ply: history.count + 1, generation: generation))
        drainIfNeeded()
        return true
    }

    /// Keeps the grades of plies up to `ply` and drops every later one, queued, running or done.
    /// A running grade of a kept ply is restarted (its result would carry the old generation);
    /// when nothing is later than `ply`, nothing changes.
    public func discard(after ply: Int) {
        guard queue.contains(where: { $0.ply > ply }) || verdicts.keys.contains(where: { $0 > ply }) else { return }
        generation += 1
        drainTask?.cancel()
        drainTask = nil
        queue = queue.filter { $0.ply <= ply }.map {
            var job = $0
            job.generation = generation
            return job
        }
        verdicts = verdicts.filter { $0.key <= ply }
        hasError = false
        drainIfNeeded()
    }

    /// Drops everything.
    public func reset() {
        discard(after: Int.min)
    }

    /// After an engine error, re-runs the grade at the head of the queue.
    public func retry() {
        guard hasError else { return }
        hasError = false
        drainIfNeeded()
    }

    private func drainIfNeeded() {
        guard drainTask == nil, !hasError, !queue.isEmpty else { return }
        drainTask = Task { [weak self] in await self?.drain() }
    }

    private func drain() async {
        while let job = queue.first {
            let outcome: Result<Verdict, any Error>
            do {
                outcome = .success(try await Self.grade(job, startFen: startFen, depth: depth, engine: engine))
            } catch {
                outcome = .failure(error)
            }
            guard job.generation == generation, !Task.isCancelled else { return }
            switch outcome {
            case .success(let verdict):
                verdicts[job.ply] = verdict
                queue.removeFirst()
            case .failure(let error):
                drainTask = nil
                if !(error is CancellationError) { hasError = true }
                return
            }
        }
        drainTask = nil
    }

    private nonisolated static func grade(_ job: Job, startFen: String, depth: Int,
                                          engine: any ChessEngine) async throws -> Verdict {
        let before = try await engine.analyze(
            AnalysisRequest(startFen: startFen, moves: job.historyBefore, depth: depth, multiPV: 2))
        let after = try await engine.analyze(
            AnalysisRequest(startFen: startFen, moves: job.historyBefore + [job.uci], depth: depth, multiPV: 2))
        return classifyPlayed(PlayedMoveInput(
            fenBefore: job.fenBefore, fenAfter: job.fenAfter, playedUci: job.uci, playedSan: job.san,
            mover: job.mover, ply: job.ply, before: before, after: after))
    }
}
