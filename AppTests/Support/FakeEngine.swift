import Foundation
import ChessCore

struct FakeEngineError: Error {}

/// Scripted engine for app tests: bot replies come from `botMoves` in order, every analysis
/// returns `result` (an even position with no best move by default).
final class FakeEngine: ChessEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var botMoves: [String]
    private let result: AnalysisResult
    private var analysisFailures = 0

    init(botMoves: [String],
         result: AnalysisResult = AnalysisResult(
             bestMove: "", lines: [PVLine(multipv: 1, depth: 16, score: Score(cp: 0), pv: [])])) {
        self.botMoves = botMoves
        self.result = result
    }

    /// The next `count` analyses throw (each failure stops one grade attempt).
    func failNextAnalyses(_ count: Int) { lock.withLock { analysisFailures = count } }

    func analyze(_ request: AnalysisRequest) async throws -> AnalysisResult {
        let fail = lock.withLock { () -> Bool in
            defer { analysisFailures = max(0, analysisFailures - 1) }
            return analysisFailures > 0
        }
        if fail { throw FakeEngineError() }
        return result
    }

    func opponentMove(startFen: String, moves: [String], elo: Int) async throws -> String {
        lock.withLock { botMoves.isEmpty ? "" : botMoves.removeFirst() }
    }
}

struct TestInstant: InstantProtocol {
    var offset: Duration

    func advanced(by duration: Duration) -> TestInstant { TestInstant(offset: offset + duration) }
    func duration(to other: TestInstant) -> Duration { other.offset - offset }
    static func < (lhs: TestInstant, rhs: TestInstant) -> Bool { lhs.offset < rhs.offset }
}

/// A clock whose sleeps finish at once, so bot pacing adds no wall time.
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
