import Foundation
import Testing
@testable import ChessCore

private let knightFen = "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"
private let gameId = UUID(uuidString: "6F1C2B3A-4D5E-4F60-8172-93A4B5C6D7E8")!

private func pv(_ score: Score, _ moves: [String]) -> PVLine {
    PVLine(multipv: 1, depth: 14, score: score, pv: moves)
}

/// Nf3-g5 hangs the knight; the engine preferred d4 exd4 Nxd4 Nxd4.
private func knightBlunder(as cls: MoveClass = .blunder, mover: Piece.Color = .white) -> Verdict {
    var v = classifyPlayed(PlayedMoveInput(
        fenBefore: knightFen,
        fenAfter: "r1bqkbnr/pppp1ppp/2n5/4p1N1/4P3/8/PPPP1PPP/RNBQKB1R b KQkq - 3 3",
        playedUci: "f3g5", playedSan: "Ng5", mover: .white, ply: 5,
        before: AnalysisResult(bestMove: "d2d4", lines: [pv(Score(cp: 20), ["d2d4", "e5d4", "f3d4", "c6d4"])]),
        after: AnalysisResult(bestMove: "d8g5", lines: [pv(Score(cp: 300), ["d8g5"])])))
    v.classification = cls
    v.mover = mover
    return v
}

private func snapshot(_ verdicts: [Verdict], userColor: Piece.Color = .white) -> GameSnapshot {
    GameSnapshot(id: gameId, date: Date(timeIntervalSince1970: 1_790_000_000), botId: "ron",
                 userColor: userColor, mode: .training, startFen: Rules.startFen,
                 moves: ["e2e4", "e7e5", "g1f3", "b8c6", "f3g5"], sans: ["e4", "e5", "Nf3", "Nc6", "Ng5"],
                 result: .ongoing, verdicts: verdicts, analysisVersion: 1, playerRatingUsed: 800)
}

@Test func blunderBecomesPuzzleWithOpponentSetupAndBestLine() throws {
    let puzzles = BlunderPuzzles.from(snapshot: snapshot([knightBlunder()]))
    #expect(puzzles.count == 1)
    let p = try #require(puzzles.first)
    #expect(p.id == "\(gameId.uuidString)-5")
    #expect(p.hasSetupMove)
    #expect(p.moves == ["b8c6", "d2d4", "e5d4", "f3d4"])
    #expect(p.solvingFen == knightFen)
    #expect(p.solverColor == .white)
    #expect(p.rating == 800)
    #expect(p.themes.contains("blunder"))

    var solver = PuzzleSolver(puzzle: p)
    solver.playSetup()
    #expect(solver.submit("f3g5") == .wrong) // the original mistake
    solver.retry()
    do { let r = solver.submit("d2d4"); #expect(r == .correct(reply: "e5d4")) }
    solver.playReply()
    do { let r = solver.submit("f3d4"); #expect(r == .solved) }
}

@Test func onlyTheUsersMistakesBecomePuzzles() {
    let snap = snapshot([knightBlunder(as: .inaccuracy), knightBlunder(as: .best)])
    #expect(BlunderPuzzles.from(snapshot: snap).isEmpty)
    #expect(BlunderPuzzles.from(snapshot: snapshot([knightBlunder()], userColor: .black)).isEmpty)
    #expect(BlunderPuzzles.from(snapshot: snapshot([knightBlunder(as: .miss)])).count == 1)
    #expect(BlunderPuzzles.from(snapshot: snapshot([knightBlunder(as: .mistake)])).count == 1)
}

@Test func blunderPuzzleWithoutGameHistoryHasNoSetup() throws {
    var snap = snapshot([knightBlunder()])
    snap.moves = []
    let p = try #require(BlunderPuzzles.from(snapshot: snap).first)
    #expect(!p.hasSetupMove)
    #expect(p.fen == knightFen)
    #expect(p.moves == ["d2d4", "e5d4", "f3d4"])
}

@Test func analysisVerdictsWinOverLiveVerdicts() {
    var snap = snapshot([])
    snap.analysis = GameAnalysis(depth: 14, verdicts: [knightBlunder()], whiteWin: [], accuracyWhite: 0, accuracyBlack: 0)
    #expect(BlunderPuzzles.from(snapshot: snap).count == 1)
}
