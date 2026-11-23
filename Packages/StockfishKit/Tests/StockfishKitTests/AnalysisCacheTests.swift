import ChessCore
@testable import StockfishKit
import Testing

struct AnalysisCacheTests {
    @Test func cacheHoldsOneEntry() {
        var c = AnalysisCache(); let a = req(["e2e4"]), b = req(["e2e4", "e7e5"])
        c.put(a, res("e7e5")); c.put(b, res("g1f3"))
        #expect(c.get(a) == nil && c.get(b) == res("g1f3"))
    }

    @Test func multiPVIsPartOfTheKey() {
        var c = AnalysisCache(); let one = req(["e2e4"])
        var three = one; three.multiPV = 3
        c.put(one, res("e7e5"))
        #expect(c.get(three) == nil && c.get(one) == res("e7e5"))
    }

    private func req(_ moves: [String]) -> AnalysisRequest {
        AnalysisRequest(startFen: Rules.startFen, moves: moves, depth: 10, multiPV: 1)
    }

    private func res(_ bestMove: String) -> AnalysisResult {
        AnalysisResult(bestMove: bestMove, lines: [])
    }
}
