import Testing
import Foundation
@testable import ChessCore

private func result(_ best: String, _ cp: Int, second: Int? = nil) -> AnalysisResult {
    var lines = [PVLine(multipv: 1, depth: 14, score: Score(cp: cp), pv: best.isEmpty ? [] : [best])]
    if let second { lines.append(PVLine(multipv: 2, depth: 14, score: Score(cp: second), pv: [])) }
    return AnalysisResult(bestMove: best, lines: lines)
}

private func script(_ engine: FakeEngine, startFen: String = Rules.startFen, moves: [String],
                    _ results: [AnalysisResult], depth: Int = 14) {
    for (i, r) in results.enumerated() {
        engine.script(AnalysisRequest(startFen: startFen, moves: Array(moves.prefix(i)), depth: depth, multiPV: 2), r)
    }
}

private let fourPly = ["e2e4", "e7e5", "g1f3", "b8c6"]

@Suite struct GameAnalyzerTests {
    @Test func analyzesBothColoursInPlyOrder() async throws {
        let engine = FakeEngine()
        // Side-to-move cp per position; Black's blunder ...e5?? is not scripted away: black to move at pos 1 sees +30.
        script(engine, moves: fourPly, [
            result("e2e4", 30), result("e7e5", 30), result("g1f3", 30), result("b8c6", 30), result("f1b5", 30),
        ])
        let a = try await GameAnalyzer(engine: engine).analyze(startFen: Rules.startFen, moves: fourPly)
        #expect(a.verdicts.count == 4)
        #expect(a.verdicts.map(\.mover) == [.white, .black, .white, .black])
        #expect(a.verdicts.map(\.ply) == [1, 2, 3, 4])
        #expect(a.verdicts.map(\.uci) == fourPly)
        #expect(a.whiteWin.count == 5)
        #expect(a.depth == 14)
        // Position 1 has Black to move with +30: White is at -30 cp.
        #expect(a.whiteWin[1] < 50 && a.whiteWin[0] > 50)
    }

    @Test func oneSearchPerPosition() async throws {
        let engine = FakeEngine()
        _ = try await GameAnalyzer(engine: engine, depth: 9).analyze(startFen: Rules.startFen, moves: fourPly)
        #expect(engine.requests.count == 5)
        for (i, r) in engine.requests.enumerated() {
            #expect(r == AnalysisRequest(startFen: Rules.startFen, moves: Array(fourPly.prefix(i)), depth: 9, multiPV: 2))
        }
    }

    @Test func finalMateIsBestNotMiss() async throws {
        // Scholar's mate after a knight shuffle, so the mating ply (11) is past the book window (ply <= 8).
        let moves = ["g1f3", "g8f6", "f3g1", "f6g8", "e2e4", "e7e5", "d1h5", "b8c6", "f1c4", "g8f6", "h5f7"]
        let engine = FakeEngine()
        var rs = (0..<11).map { _ in result("a2a3", 0) }
        rs[10] = AnalysisResult(bestMove: "h5f7", lines: [PVLine(multipv: 1, depth: 14, score: Score(mate: 1), pv: ["h5f7"])])
        rs.append(AnalysisResult(bestMove: "", lines: [PVLine(multipv: 1, depth: 14, score: Score(mate: 0), pv: [])]))
        script(engine, moves: moves, rs)
        let a = try await GameAnalyzer(engine: engine).analyze(startFen: Rules.startFen, moves: moves)
        let last = try #require(a.verdicts.last)
        #expect(last.classification == .best || last.classification == .great)
        #expect(last.uci == "h5f7")
        #expect(a.whiteWin.last == winPercent(10000))
    }

    @Test func customStartFen() async throws {
        let fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
        let moves = ["e7e5", "g1f3"]
        let engine = FakeEngine()
        let a = try await GameAnalyzer(engine: engine).analyze(startFen: fen, moves: moves)
        #expect(a.verdicts.map(\.mover) == [.black, .white])
        #expect(engine.requests.allSatisfy { $0.startFen == fen })
        #expect(a.verdicts[0].facts.fenBefore == fen)
    }

    @Test func cancellationStops() async throws {
        let engine = FakeEngine()
        engine.analysisGate.close()
        let task = Task { try await GameAnalyzer(engine: engine).analyze(startFen: Rules.startFen, moves: fourPly) }
        while engine.analysisGate.waiterCount == 0 { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(engine.requests.count == 1)
    }

    @Test func progressReportsEveryPosition() async throws {
        final class Box: @unchecked Sendable { let lock = NSLock(); var calls: [[Int]] = [] }
        let box = Box()
        _ = try await GameAnalyzer(engine: FakeEngine()).analyze(startFen: Rules.startFen, moves: fourPly) { d, t in
            box.lock.withLock { box.calls.append([d, t]) }
        }
        #expect(box.calls == [[1, 5], [2, 5], [3, 5], [4, 5], [5, 5]])
    }

    @Test func engineErrorThrows() async throws {
        let engine = FakeEngine()
        engine.failNextAnalyze()
        await #expect(throws: FakeEngineError.self) {
            try await GameAnalyzer(engine: engine).analyze(startFen: Rules.startFen, moves: fourPly)
        }
    }

    @Test func oneMoveGameHasFiniteAccuraciesAndEncodes() async throws {
        let a = try await GameAnalyzer(engine: FakeEngine()).analyze(startFen: Rules.startFen, moves: ["e2e4"])
        #expect(a.accuracyWhite.isFinite && a.accuracyBlack.isFinite)
        #expect(a.whiteWin.allSatisfy { $0.isFinite })
        _ = try JSONEncoder().encode(a)
    }

    @Test func zeroMoveGameIsFinite() async throws {
        let a = try await GameAnalyzer(engine: FakeEngine()).analyze(startFen: Rules.startFen, moves: [])
        #expect(a.verdicts.isEmpty && a.whiteWin.count == 1)
        _ = try JSONEncoder().encode(a)
    }

    @Test func illegalMoveThrows() async throws {
        await #expect(throws: GameAnalyzerError.illegalMove(ply: 0, uci: "e2e5")) {
            try await GameAnalyzer(engine: FakeEngine()).analyze(startFen: Rules.startFen, moves: ["e2e5"])
        }
    }
}
