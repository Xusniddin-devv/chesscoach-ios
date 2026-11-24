import Testing
@testable import ChessCore

private func puzzle(_ fen: String, _ moves: [String], _ themes: [String]) -> Puzzle {
    Puzzle(id: "t", fen: fen, moves: moves, rating: 1000, themes: themes, hasSetupMove: false)
}

@Suite struct PuzzleExplainerTests {
    @Test func forkNamesBothTargetsAsChips() {
        let p = puzzle("r3k3/8/8/3N4/8/8/8/4K3 w - - 0 1", ["d5c7"], ["fork"])
        #expect(PuzzleExplainer.line(for: p) == "**Nc7+** hits the king on [e8] and the rook on [a8] at once.")
    }

    @Test func backRankMate() {
        let p = puzzle("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1", ["a1a8"], ["mateIn1", "backRankMate"])
        #expect(PuzzleExplainer.line(for: p) == "**Ra8#** mates on the back rank.")
    }

    @Test func hangingPieceIsTaken() {
        let p = puzzle("4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1", ["d1d5"], ["hangingPiece"])
        #expect(PuzzleExplainer.line(for: p) == "**Rxd5** takes the queen on [d5]. Nothing was guarding it.")
    }

    @Test func everyBankPuzzleGetsALine() {
        for p in PuzzleBank.all.prefix(500) {
            #expect(PuzzleExplainer.line(for: p) != nil, "\(p.id)")
        }
    }
}
