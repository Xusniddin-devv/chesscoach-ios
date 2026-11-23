import ChessCore
@testable import StockfishKit
import Testing

struct UCIParserTests {
    @Test func parsesInfoWithMateAndMultipv() {
        let l = UCIParser.info("info depth 12 seldepth 18 multipv 2 score mate -3 nodes 1 pv e2e4 e7e5")!
        #expect(l == PVLine(multipv: 2, depth: 12, score: Score(cp: nil, mate: -3), pv: ["e2e4", "e7e5"]))
        #expect(UCIParser.info("info depth 5 currmove e2e4 currmovenumber 1") == nil)
        #expect(UCIParser.bestMove("bestmove (none)") == "")
    }

    @Test func parsesCentipawnInfoWithoutMultipv() {
        let l = UCIParser.info("info depth 8 seldepth 10 score cp -35 wdl 10 900 90 nodes 99 pv g1f3")
        #expect(l == PVLine(multipv: 1, depth: 8, score: Score(cp: -35, mate: nil), pv: ["g1f3"]))
        #expect(UCIParser.info("info string NNUE evaluation using nn.nnue") == nil)
    }

    @Test func parsesBestMoveWithPonder() {
        #expect(UCIParser.bestMove("bestmove e2e4 ponder e7e5") == "e2e4")
        #expect(UCIParser.bestMove("readyok") == nil)
    }
}
