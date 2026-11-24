import Testing
import Foundation
@testable import ChessCore

private func game(_ moves: [String], user: Piece.Color = .white, result: GameResult = .whiteWins) -> GameSnapshot {
    GameSnapshot(id: UUID(), date: .now, botId: "lichess", userColor: user, mode: .silent, startFen: Rules.startFen,
                 moves: moves, sans: [], result: result, verdicts: [], analysisVersion: 1, playerRatingUsed: 900,
                 source: "lichess", opponentName: "opp")
}

private func verdict(ply: Int, mover: Piece.Color, cls: MoveClass, motifs: [Motif], drop: Double,
                     uci: String = "e2e4", best: String = "d2d4", fen: String = Rules.startFen) -> Verdict {
    Verdict(ply: ply, san: "x", uci: uci, mover: mover, classification: cls, cpLoss: 300, winDrop: drop, evalWhiteCp: 0,
            mateBefore: nil, mateAfter: nil, bestMove: best, bestSan: "y", bestLineSan: [], motifs: motifs,
            facts: MoveFacts(fenBefore: fen, fenAfter: fen, playedUci: uci, playedSan: "x", bestUci: best, bestPv: [best],
                             bestReplyUci: "", cpLoss: 300, evalAfterWhiteCp: 0, mateForMoverBefore: nil,
                             mateAgainstMoverAfter: nil, moveNumber: (ply + 1) / 2, mover: mover))
}

private func analysed(_ verdicts: [Verdict], user: Piece.Color = .white, acc: Double = 70,
                      result: GameResult = .blackWins) -> GameSnapshot {
    var g = game(["e2e4"], user: user, result: result)
    g.analysis = GameAnalysis(depth: 12, verdicts: verdicts, whiteWin: [50, 50],
                              accuracyWhite: user == .white ? acc : 50, accuracyBlack: user == .black ? acc : 50)
    return g
}

@Suite struct OnboardingAnalysisTests {
    @Test func analysesEachGameInOrderWithProgress() async {
        let engine = FakeEngine()
        let games = [game(["e2e4", "e7e5"]), game(["d2d4"]), game(["e2e4", "zz99"])]
        let log = EventLog()
        let out = await OnboardingAnalysis(engine: engine).run(games) { log.append($0) }
        #expect(out.count == 3)
        #expect(out[0].analysis?.depth == 12 && out[1].analysis != nil)
        #expect(out[2].analysis == nil)  // illegal move: kept, unanalysed
        let events = log.events
        #expect(events.first == .gameStarted(index: 0, total: 3))
        #expect(events.contains(.position(index: 0, done: 3, positions: 3)))
        #expect(events.contains(.gameFailed(index: 2)))
        #expect(events.filter { if case .gameFinished = $0 { true } else { false } }.count == 2)
        #expect(engine.requests.allSatisfy { $0.depth == 12 })
    }

    @Test func weaknessReportRanksMotifsByCountThenGames() {
        let g1 = analysed([
            verdict(ply: 1, mover: .white, cls: .blunder, motifs: [.hangingPiece], drop: 30),
            verdict(ply: 3, mover: .white, cls: .mistake, motifs: [.hangingPiece, .allowedFork], drop: 12),
            verdict(ply: 2, mover: .black, cls: .blunder, motifs: [.missedMate], drop: 40),  // opponent: ignored
        ], acc: 60)
        let g2 = analysed([
            verdict(ply: 2, mover: .black, cls: .blunder, motifs: [.allowedFork], drop: 50),
            verdict(ply: 4, mover: .black, cls: .inaccuracy, motifs: [.hangingPiece], drop: 5),  // not costly enough
        ], user: .black, acc: 80)
        let r = WeaknessReport([g1, g2, game(["e2e4"])])
        #expect(r.gamesAnalysed == 2)
        #expect(r.averageAccuracy == 70)
        #expect(r.top == [.allowedFork, .hangingPiece])  // 2 each; forks in 2 games
        #expect(r.weaknesses[0].example?.winDrop == 50)
        #expect(r.weaknesses[0].exampleGameId == g2.id)
        #expect(r.blunders == 2 && r.mistakes == 1)
    }

    @Test func commentaryNamesTheHangingPieceAndSquare() {
        let fen = "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 2"
        let g = analysed([verdict(ply: 3, mover: .white, cls: .blunder, motifs: [.hangingPiece], drop: 30,
                                  uci: "f3g5", fen: fen)], result: .whiteWins)
        let line = CoachCommentary.afterGame(index: 3, snapshot: g)
        #expect(line.mood == .concerned)
        #expect(line.text == "Game 4: your knight on [g5] was left hanging on move 2. Noted. You won anyway.")
        let clean = CoachCommentary.afterGame(index: 0, snapshot: analysed([], acc: 92))
        #expect(clean.mood == .pleased && clean.text.contains("92 accuracy"))
    }
}

final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [OnboardingEvent] = []
    var events: [OnboardingEvent] { lock.withLock { _events } }
    func append(_ e: OnboardingEvent) { lock.withLock { _events.append(e) } }
}

@Suite struct RatingTierTests {
    @Test func tiersFollowTheProfileConcept() {
        #expect(RatingTier(rating: 799) == .pawn)
        #expect(RatingTier(rating: 800) == .knight)
        #expect(RatingTier(rating: 940) == .knight)
        #expect(RatingTier(rating: 1200) == .bishop)
        #expect(RatingTier(rating: 1799) == .rook)
        #expect(RatingTier(rating: 1800) == .queen)
        #expect(RatingTier(rating: 2100) == .king)
        #expect(RatingTier.pointsToNext(from: 1140) == 60)
        #expect(RatingTier.pointsToNext(from: 2500) == nil)
    }
}

@Suite struct GoalModelTests {
    @Test func distributionIsMonotoneAndBucketsSumToAll() {
        for d in [RatingDistribution.chesscom, .lichess] {
            let ratings = stride(from: 100, through: 3000, by: 50).map { d.below($0) }
            #expect(zip(ratings, ratings.dropFirst()).allSatisfy { $0 <= $1 })
            #expect(abs(d.buckets.map(\.share).reduce(0, +) - 100) < 0.001)
        }
        #expect(RatingDistribution.chesscom.topPercent(1200) == 14.5)
        #expect(RatingDistribution.lichess.topPercent(1500) == 64)
        #expect(RatingDistribution.chesscom.topPercent(3000) == 0.1)
    }

    @Test func monthlyGainFallsWithRating() {
        #expect(GoalModel.monthlyGain(at: 600) == 70)
        #expect(GoalModel.monthlyGain(at: 1700) < GoalModel.monthlyGain(at: 900))
        #expect(GoalModel.expectedGain(from: 940, months: 3) > 140 && GoalModel.expectedGain(from: 940, months: 3) < 160)
    }

    @Test func chanceIsClampedAndOrdered() {
        #expect(GoalModel.chance(current: 940, target: 900, months: 3) == 97)
        #expect(GoalModel.chance(current: 940, target: 2000, months: 1) == 3)
        let c3 = GoalModel.chance(current: 940, target: 1100, months: 3)
        let c6 = GoalModel.chance(current: 940, target: 1100, months: 6)
        #expect(c3 > 20 && c3 < 60)
        #expect(c6 > c3)
        // Exactly the expected gain: a coin flip.
        let expected = Int(GoalModel.expectedGain(from: 1000, months: 6).rounded())
        #expect(abs(GoalModel.chance(current: 1000, target: 1000 + expected, months: 6) - 50) <= 1)
    }

    @Test func verdictCopy() {
        #expect(GoalModel.verdict(chance: 18, months: 3) == "Ambitious. About 18 in 100 players who practise daily get there in 3 months.")
        #expect(GoalModel.verdict(chance: 80, months: 1).hasPrefix("Very doable"))
        #expect(GoalModel.suggestedTarget(current: 940) % 50 == 0)
    }
}

@Suite struct TrainingPlanTests {
    @Test func sevenDaysFromTheTopWeaknesses() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let plan = TrainingPlan.make(weaknesses: [.allowedFork, .hangingPiece], rating: 950, ownMistakes: 8, now: now)
        #expect(plan.days.count == 7)
        #expect(plan.focus == [.allowedFork, .hangingPiece, .missedMate])
        // Day 1: own mistakes + the free first lesson of the track.
        #expect(plan.days[0].tasks.map(\.kind) == [.ownMistakes, .lesson])
        let firstLesson = try? #require(plan.days[0].tasks[1].lessonId)
        #expect(firstLesson == LessonLibrary.lessons(in: .endgames).first?.id)
        // Puzzle tasks are themed, near the rating, and never repeat a puzzle.
        let puzzleTasks = plan.days.flatMap(\.tasks).filter { $0.kind == .puzzles }
        let ids = puzzleTasks.flatMap(\.puzzleIds)
        #expect(!ids.isEmpty && Set(ids).count == ids.count)
        for task in puzzleTasks {
            let themes = Set(PuzzleBank.themes(for: task.motif!))
            for id in task.puzzleIds { #expect(!themes.isDisjoint(with: PuzzleBank.puzzle(id: id)!.themes)) }
        }
        // Sparring partner and the test-day step up.
        #expect(plan.days[1].tasks.last?.botId == "ron")
        #expect(plan.days[6].tasks.last?.botId == "cadet")
        #expect(plan.dayIndex(on: now) == 0)
        #expect(plan.dayIndex(on: now.addingTimeInterval(6 * 86_400 + 60)) == 6)
        #expect(plan.dayIndex(on: now.addingTimeInterval(8 * 86_400)) == nil)
    }

    @Test func noOwnMistakesStartsWithBankPuzzles() {
        let plan = TrainingPlan.make(weaknesses: [], rating: 500, ownMistakes: 0)
        #expect(plan.days[0].tasks.first?.kind == .puzzles)
        #expect(plan.focus == TrainingPlan.defaultFocus)
        #expect(TrainingPlan.recommendedBot(rating: 500).id == "pip")
        #expect(TrainingPlan.recommendedBot(rating: 2500).id == "apex")
    }

    @Test func newPlayerAnswersEstimateAndSteer() {
        let a = NewPlayerAnswers(rules: .learning, played: .never, goal: .checkmates)
        #expect(a.estimatedRating == 400)
        #expect(NewPlayerAnswers(rules: .knowTactics, played: .lots, goal: .winMore).estimatedRating == 1000)
        let plan = TrainingPlan.make(weaknesses: a.weaknesses, rating: a.estimatedRating, ownMistakes: 0, preferredTrack: a.track)
        #expect(plan.focus.first == .missedMate)
        #expect(plan.days[0].tasks.contains { $0.lessonId == LessonLibrary.lessons(in: .checkmates).first?.id })
    }

    @Test func planRoundTripsAsJSON() throws {
        let plan = TrainingPlan.make(weaknesses: [.missedCapture], rating: 1300, ownMistakes: 2)
        let data = try JSONEncoder().encode(plan)
        #expect(try JSONDecoder().decode(TrainingPlan.self, from: data) == plan)
    }
}
