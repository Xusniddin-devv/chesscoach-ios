import Foundation
import Testing
@testable import ChessCore

private let startFen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
private let afterE4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"

private func res(best: String, _ scores: Score..., pv: [String] = []) -> AnalysisResult {
    AnalysisResult(bestMove: best, lines: scores.enumerated().map {
        PVLine(multipv: $0.offset + 1, depth: 12, score: $0.element, pv: pv)
    })
}

/// White mover from the start position playing e2e4. `whiteAfterCp` is White-relative;
/// the after-score is reported from Black's view (side to move).
private func e4Input(ply: Int = 20, best: String = "e2e4", before: [Int], whiteAfterCp: Int) -> PlayedMoveInput {
    PlayedMoveInput(
        fenBefore: startFen, fenAfter: afterE4, playedUci: "e2e4", playedSan: "e4",
        mover: .white, ply: ply,
        before: AnalysisResult(bestMove: best, lines: before.enumerated().map {
            PVLine(multipv: $0.offset + 1, depth: 12, score: Score(cp: $0.element), pv: [best])
        }),
        after: res(best: "e7e5", Score(cp: -whiteAfterCp), pv: ["e7e5", "g1f3"]))
}

@Test func forcedWhenOneLegalMove() {
    let before = "7k/8/8/8/8/8/6q1/7K w - - 0 1"
    #expect(Rules.legalMoveCount(fen: before) == 1)
    let v = classifyPlayed(PlayedMoveInput(
        fenBefore: before, fenAfter: "7k/8/8/8/8/8/6K1/8 b - - 0 1",
        playedUci: "h1g2", playedSan: "Kxg2", mover: .white, ply: 20,
        before: res(best: "h1g2", Score(cp: -900)), after: res(best: "h8g8", Score(cp: 0))))
    #expect(v.classification == .forced)
}

@Test func missFromWinningToBelow70() {
    let v = classifyPlayed(e4Input(best: "d2d4", before: [500], whiteAfterCp: 100))
    #expect(v.classification == .miss)
    #expect(v.cpLoss == 400)
}

@Test func brilliantRookSacrifice() {
    let v = classifyPlayed(PlayedMoveInput(
        fenBefore: "4k3/8/1p6/8/8/8/8/2R1K3 w - - 0 1",
        fenAfter: "4k3/8/1p6/2R5/8/8/8/4K3 b - - 1 1",
        playedUci: "c1c5", playedSan: "Rc5", mover: .white, ply: 20,
        before: res(best: "c1c5", Score(cp: 50)), after: res(best: "b6c5", Score(cp: -50))))
    #expect(v.classification == .brilliant)
}

@Test func queenTradeIsNeverBrilliant() {
    let v = classifyPlayed(PlayedMoveInput(
        fenBefore: "4k3/8/6Q1/8/7p/6q1/8/4K3 w - - 0 1",
        fenAfter: "4k3/8/8/8/7p/6Q1/8/4K3 b - - 0 1",
        playedUci: "g6g3", playedSan: "Qxg3", mover: .white, ply: 30,
        before: res(best: "g6g3", Score(cp: 0)), after: res(best: "h4g3", Score(cp: 0))))
    #expect(v.classification == .best)
}

@Test func bookIsPlyAtMost8AndLossAtMost35() {
    let v = classifyPlayed(e4Input(ply: 3, best: "d2d4", before: [30], whiteAfterCp: 10))
    #expect(v.cpLoss == 20)
    #expect(v.classification == .book)
    let late = classifyPlayed(e4Input(ply: 9, best: "d2d4", before: [30], whiteAfterCp: 10))
    #expect(late.classification == .excellent)
}

@Test func greatNeedsGap150() {
    #expect(classifyPlayed(e4Input(before: [200, 40], whiteAfterCp: 200)).classification == .great)
    #expect(classifyPlayed(e4Input(before: [200, 100], whiteAfterCp: 200)).classification == .best)
}

@Test func blunderMistakeInaccuracyByWinDrop() {
    let blunder = classifyPlayed(e4Input(best: "d2d4", before: [0], whiteAfterCp: -300))
    #expect(blunder.classification == .blunder)
    #expect(blunder.winDrop == 25.1)
    let mistake = classifyPlayed(e4Input(best: "d2d4", before: [0], whiteAfterCp: -150))
    #expect(mistake.classification == .mistake)
    #expect(mistake.winDrop == 13.5)
    let inaccuracy = classifyPlayed(e4Input(best: "d2d4", before: [0], whiteAfterCp: -80))
    #expect(inaccuracy.classification == .inaccuracy)
    #expect(inaccuracy.winDrop == 7.3)
}

@Test func excellentVsGood() {
    let excellent = classifyPlayed(e4Input(best: "d2d4", before: [30], whiteAfterCp: 15))
    #expect(excellent.cpLoss == 15)
    #expect(excellent.classification == .excellent)
    let good = classifyPlayed(e4Input(best: "d2d4", before: [30], whiteAfterCp: 0))
    #expect(good.cpLoss == 30)
    #expect(good.winDrop < 5)
    #expect(good.classification == .good)
}

@Test func neverSuggestsPlayedMoveAsBetter() {
    let v = classifyPlayed(e4Input(before: [30], whiteAfterCp: 30))
    #expect(v.bestMove == "e2e4")
    #expect(v.bestSan == "e4")
    #expect([MoveClass.best, .great, .book].contains(v.classification))
    #expect(v.bestLineSan == ["e5", "Nf3"])
}

@Test func mateScoresSurviveIntoFacts() {
    let v = classifyPlayed(PlayedMoveInput(
        fenBefore: startFen, fenAfter: afterE4, playedUci: "e2e4", playedSan: "e4",
        mover: .white, ply: 20,
        before: res(best: "d2d4", Score(mate: 2)), after: res(best: "d8h4", Score(mate: 1))))
    #expect(v.facts.mateForMoverBefore == 2)
    #expect(v.facts.mateAgainstMoverAfter == 1)
    #expect(v.mateBefore == 2 && v.mateAfter == 1)
    #expect(v.classification == .miss)
}

@Test func blackMoverSignsAndRounding() {
    // Black plays e7e5 after 1.e4; before cp is Black's view (+20).
    let fenB = afterE4
    let fenA = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"
    let v = classifyPlayed(PlayedMoveInput(
        fenBefore: fenB, fenAfter: fenA, playedUci: "e7e5", playedSan: "e5", mover: .black, ply: 20,
        before: res(best: "c7c5", Score(cp: 20)), after: res(best: "g1f3", Score(cp: 50))))
    // s = -20 (white cp), c = +50: black loses 70 cp
    #expect(v.cpLoss == 70)
    #expect(v.evalWhiteCp == 50)
    #expect(v.facts.moveNumber == 1)
}

@Test func verdictCodableRoundTrip() throws {
    let v = classifyPlayed(e4Input(before: [30], whiteAfterCp: 30))
    let data = try JSONEncoder().encode(v)
    #expect(try JSONDecoder().decode(Verdict.self, from: data) == v)
}
