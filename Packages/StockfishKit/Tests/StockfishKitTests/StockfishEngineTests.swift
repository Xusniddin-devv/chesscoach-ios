import ChessCore
@testable import StockfishKit
import Testing

extension GlobalEngineSuite {
    /// Uses the process-wide engine; each test leaves it running and idle.
    @Suite struct StockfishEngineTests {
        @Test func concurrentAnalysesDoNotCross() async throws {  // web bug: crossed results
            let e = StockfishEngine.shared
            async let x = e.analyze(AnalysisRequest(startFen: "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", moves: [], depth: 10, multiPV: 1))
            async let y = e.analyze(AnalysisRequest(startFen: Rules.startFen, moves: [], depth: 10, multiPV: 1))
            let (rx, ry) = try await (x, y)
            #expect(rx.bestMove == "d1d8" && rx.lines[0].score.mate == 1)
            #expect(Rules.apply(uci: ry.bestMove, to: Rules.startFen) != nil)
        }

        @Test func identicalRequestIsServedFromCache() async throws {
            let e = StockfishEngine.shared
            let r = AnalysisRequest(startFen: Rules.startFen, moves: ["e2e4"], depth: 8, multiPV: 2)
            let before = await e.searchCount
            let first = try await e.analyze(r); let second = try await e.analyze(r)
            #expect(await e.searchCount == before + 1)
            #expect(first == second && first.lines.map(\.multipv) == [1, 2])
        }

        @Test func terminalPositionReturnsNoMove() async throws {  // Review Focus 4
            let r = try await StockfishEngine.shared.analyze(AnalysisRequest(startFen: "7k/6Q1/6K1/8/8/8/8/8 b - - 0 1", moves: [], depth: 6, multiPV: 2))
            #expect(r.bestMove == "")
        }

        @Test func restartRecoversAfterQuit() async throws {  // Review Focus 5
            let e = StockfishEngine.shared
            _ = try await e.analyze(.init(startFen: Rules.startFen, moves: [], depth: 4, multiPV: 1))
            await e.restart()
            let before = await e.searchCount
            #expect(try await e.analyze(.init(startFen: Rules.startFen, moves: [], depth: 4, multiPV: 1)).bestMove.isEmpty == false)
            #expect(await e.searchCount == before + 1)
        }

        @Test func opponentReturnsLegalMove() async throws {
            let uci = try await StockfishEngine.shared.opponentMove(startFen: Rules.startFen, moves: ["e2e4"], elo: 600)
            #expect(Rules.apply(uci: uci, to: Rules.fen(startFen: Rules.startFen, moves: ["e2e4"])!) != nil)
        }

        @Test func analysisAfterOpponentRestoresAnalystOptions() async throws {
            let e = StockfishEngine.shared
            _ = try await e.opponentMove(startFen: Rules.startFen, moves: [], elo: 600)  // Skill Level 0, MultiPV 1
            let r = try await e.analyze(.init(startFen: "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", moves: [], depth: 10, multiPV: 3))
            #expect(r.bestMove == "d1d8" && r.lines.map(\.multipv) == [1, 2, 3])
        }

        @Test func sendsHistoryNotBareFen() async throws {
            let e = StockfishEngine.shared
            _ = try await e.analyze(.init(startFen: Rules.startFen, moves: ["e2e4", "e7e5"], depth: 2, multiPV: 1))
            #expect(await e.lastPositionCommand == "position fen \(Rules.startFen) moves e2e4 e7e5")
        }

        @Test func sendsBareFenWithoutMoves() async throws {
            let e = StockfishEngine.shared
            _ = try await e.analyze(.init(startFen: Rules.startFen, moves: [], depth: 3, multiPV: 1))
            #expect(await e.lastPositionCommand == "position fen \(Rules.startFen)")
        }
    }
}
