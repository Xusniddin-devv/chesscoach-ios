import Foundation
import Testing
@testable import ChessCore

@Test func guessPointsFollowTheBands() {
    #expect(GuessScoring.points(isBest: true, cpLoss: 400) == 3)
    #expect(GuessScoring.points(isBest: false, cpLoss: 0) == 2)
    #expect(GuessScoring.points(isBest: false, cpLoss: 50) == 2)
    #expect(GuessScoring.points(isBest: false, cpLoss: 51) == 1)
    #expect(GuessScoring.points(isBest: false, cpLoss: 150) == 1)
    #expect(GuessScoring.points(isBest: false, cpLoss: 151) == 0)
    #expect(GuessScoring.points(isBest: false, cpLoss: -20) == 2)
}

@Test func guessTotal() {
    func r(_ points: Int) -> GuessResult {
        GuessResult(ply: points, guessUci: "", guessSan: "", guessClass: .good, cpLoss: 0, playedUci: "",
                    playedSan: "", playedClass: .good, bestUci: "", bestSan: "", points: points)
    }
    #expect(GuessScoring.total([r(3), r(0), r(2)]) == (5, 9))
    #expect(GuessScoring.total([]) == (0, 0))
}

private func line(_ cp: Int, _ pv: [String] = []) -> PVLine {
    PVLine(multipv: 1, depth: 14, score: Score(cp: cp), pv: pv)
}

/// 1. e4 (played, an inaccuracy against the saved best d4) e5.
private func sampleAnalysis() -> GameAnalysis {
    let e4 = classifyPlayed(PlayedMoveInput(
        fenBefore: Rules.startFen, fenAfter: Rules.fen(startFen: Rules.startFen, moves: ["e2e4"])!,
        playedUci: "e2e4", playedSan: "e4", mover: .white, ply: 1,
        before: AnalysisResult(bestMove: "d2d4", lines: [line(40, ["d2d4"])]),
        after: AnalysisResult(bestMove: "e7e5", lines: [line(-10, ["e7e5"])])))
    let e5 = classifyPlayed(PlayedMoveInput(
        fenBefore: Rules.fen(startFen: Rules.startFen, moves: ["e2e4"])!,
        fenAfter: Rules.fen(startFen: Rules.startFen, moves: ["e2e4", "e7e5"])!,
        playedUci: "e7e5", playedSan: "e5", mover: .black, ply: 2,
        before: AnalysisResult(bestMove: "e7e5", lines: [line(-10, ["e7e5"])]),
        after: AnalysisResult(bestMove: "g1f3", lines: [line(10, ["g1f3"])])))
    return GameAnalysis(depth: 14, verdicts: [e4, e5], whiteWin: [50, 50, 50], accuracyWhite: 90, accuracyBlack: 90)
}

@Test func guessingTheGameMoveUsesTheSavedVerdict() async throws {
    let engine = FakeEngine()
    let analysis = sampleAnalysis()
    let result = try #require(try await GuessScoring.grade(
        guess: "e2e4", ply: 1, startFen: Rules.startFen, moves: ["e2e4", "e7e5"], analysis: analysis, engine: engine))
    #expect(result.matchedGame)
    #expect(result.cpLoss == analysis.verdicts[0].cpLoss)
    #expect(result.points == GuessScoring.points(isBest: false, cpLoss: analysis.verdicts[0].cpLoss))
    #expect(result.bestSan == "d4")
    #expect(engine.requests.isEmpty)
}

@Test func guessingTheSavedBestMoveScoresThreeWithoutTheEngine() async throws {
    let engine = FakeEngine()
    let result = try #require(try await GuessScoring.grade(
        guess: "d2d4", ply: 1, startFen: Rules.startFen, moves: ["e2e4", "e7e5"], analysis: sampleAnalysis(), engine: engine))
    #expect(result.points == 3)
    #expect(result.guessClass == .best)
    #expect(result.guessSan == "d4")
    #expect(engine.requests.isEmpty)
}

@Test func otherGuessesAreSearchedAtDepth14MultiPV3() async throws {
    let engine = FakeEngine()
    let before = AnalysisRequest(startFen: Rules.startFen, moves: [], depth: 14, multiPV: 3)
    let after = AnalysisRequest(startFen: Rules.startFen, moves: ["c2c4"], depth: 14, multiPV: 3)
    engine.script(before, AnalysisResult(bestMove: "d2d4", lines: [line(40, ["d2d4"])]))
    // Black to move after c4: −0 for Black = White +0 → 40 cp worse than d4.
    engine.script(after, AnalysisResult(bestMove: "e7e5", lines: [line(0, ["e7e5"])]))
    let result = try #require(try await GuessScoring.grade(
        guess: "c2c4", ply: 1, startFen: Rules.startFen, moves: ["e2e4", "e7e5"], analysis: sampleAnalysis(), engine: engine))
    #expect(engine.requests == [before, after])
    #expect(result.cpLoss == 40)
    #expect(result.points == 2)
    #expect(result.playedSan == "e4")

    let bad = AnalysisRequest(startFen: Rules.startFen, moves: ["g2g4"], depth: 14, multiPV: 3)
    engine.script(bad, AnalysisResult(bestMove: "d7d5", lines: [line(160, ["d7d5"])]))
    let g4 = try #require(try await GuessScoring.grade(
        guess: "g2g4", ply: 1, startFen: Rules.startFen, moves: ["e2e4", "e7e5"], analysis: sampleAnalysis(), engine: engine))
    #expect(g4.cpLoss == 200)
    #expect(g4.points == 0)
}

@Test func illegalGuessOrPlyWithoutVerdictGivesNil() async throws {
    let engine = FakeEngine()
    let a = try await GuessScoring.grade(guess: "e2e5", ply: 1, startFen: Rules.startFen, moves: ["e2e4"],
                                         analysis: sampleAnalysis(), engine: engine)
    let b = try await GuessScoring.grade(guess: "e2e4", ply: 5, startFen: Rules.startFen, moves: ["e2e4"],
                                         analysis: sampleAnalysis(), engine: engine)
    #expect(a == nil)
    #expect(b == nil)
}
