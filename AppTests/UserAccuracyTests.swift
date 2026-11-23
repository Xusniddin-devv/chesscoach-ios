import Testing
import ChessCore
@testable import ChessCoach

struct UserAccuracyTests {
    /// A real verdict (Verdict has no public memberwise init) with the fields the helper reads set.
    private func verdict(ply: Int, mover: Piece.Color, winDrop: Double, evalWhiteCp: Int) -> Verdict {
        let even = AnalysisResult(bestMove: "e2e4", lines: [PVLine(multipv: 1, depth: 16, score: Score(cp: 0), pv: [])])
        var v = classifyPlayed(PlayedMoveInput(
            fenBefore: Rules.startFen, fenAfter: Rules.apply(uci: "e2e4", to: Rules.startFen)!.fenAfter,
            playedUci: "e2e4", playedSan: "e4", mover: .white, ply: 1, before: even, after: even))
        v.ply = ply
        v.mover = mover
        v.winDrop = winDrop
        v.evalWhiteCp = evalWhiteCp
        return v
    }

    @Test func noUserMovesHasNoAccuracy() {
        #expect(userAccuracy(verdicts: [], userColor: .white) == nil)
    }

    /// One move losing 20 win-% scores 103.1668·e^(−0.04354·20) − 3.1669 ≈ 40.0, for either colour.
    @Test(arguments: [Piece.Color.white, .black])
    func singleMoveUsesItsWinDrop(color: Piece.Color) {
        let ply = color == .white ? 1 : 2
        let v = verdict(ply: ply, mover: color, winDrop: 20, evalWhiteCp: 300)
        #expect(userAccuracy(verdicts: [v], userColor: color) == 40.0)
    }

    @Test func perfectMovesScore100AcrossBotReplies() {
        // Evals swing between the user's moves: the bot's implicit moves carry the swing.
        let vs = [verdict(ply: 2, mover: .black, winDrop: 0, evalWhiteCp: 50),
                  verdict(ply: 4, mover: .black, winDrop: 0, evalWhiteCp: 400),
                  verdict(ply: 6, mover: .black, winDrop: 0, evalWhiteCp: -200)]
        #expect(userAccuracy(verdicts: vs, userColor: .black) == 100)
    }

    @Test func opponentVerdictsAreIgnored() {
        let user = verdict(ply: 1, mover: .white, winDrop: 20, evalWhiteCp: 0)
        let other = verdict(ply: 2, mover: .black, winDrop: 50, evalWhiteCp: 0)
        #expect(userAccuracy(verdicts: [user, other], userColor: .white) == 40.0)
    }
}
