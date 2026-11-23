import Foundation
import Testing
@testable import ChessCore

private let startFen = Rules.startFen
private let pip = Bot.all[0]  // Elo 600: thinkTimeMs(elo: 600, jitter: 0.5) == 450

private func result(best: String, cp: Int) -> AnalysisResult {
    AnalysisResult(bestMove: best, lines: [
        PVLine(multipv: 1, depth: 16, score: Score(cp: cp), pv: best.isEmpty ? [] : [best]),
    ])
}

private func gradeRequest(_ moves: [String], startFen: String = startFen) -> AnalysisRequest {
    AnalysisRequest(startFen: startFen, moves: moves, depth: 16, multiPV: 2)
}

@MainActor
private func makeSession(_ engine: FakeEngine, mode: PlayMode = .silent, userColor: Piece.Color = .white,
                         startFen: String = startFen,
                         clock: any _Concurrency.Clock<Duration> = ImmediateClock()) -> GameSession {
    GameSession(bot: pip, userColor: userColor, mode: mode, engine: engine,
                startFen: startFen, clock: clock, jitter: { 0.5 })
}

/// Yields the main actor until `condition` holds or a wall-clock deadline passes (no sleeping).
@MainActor
private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(3)
    while !condition() {
        if clock.now >= deadline { return false }
        await Task.yield()
    }
    return true
}

/// Lets queued main-actor and engine work run before a negative assertion.
@MainActor
private func settle() async {
    for _ in 0..<500 { await Task.yield() }
}

private func isInterrupted(_ phase: GameSession.Phase) -> Bool {
    if case .interrupted = phase { return true }
    return false
}

// MARK: - Grading queue

@MainActor @Test func fastMovesAreGradedInOrderWithOwnHistory() async {
    let history = ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "d2d3", "f8c5"]
    let engine = FakeEngine(botMoves: ["e7e5", "b8c6", "g8f6", "f8c5"])
    engine.analysisGate.close()
    let session = makeSession(engine, mode: .silent)
    session.start()

    for i in stride(from: 0, to: history.count, by: 2) {
        #expect(session.userMove(history[i]))
        #expect(await eventually { session.phase == .userTurn && session.moves.count == i + 2 })
    }
    #expect(session.moves == history)
    // The engine is held on the first grade; the queue must not fire the others concurrently.
    #expect(engine.requests == [gradeRequest([])])
    #expect(session.verdicts.isEmpty)

    engine.analysisGate.open()
    #expect(await eventually { session.verdicts.count == 4 })

    #expect(session.verdicts.keys.sorted() == [1, 3, 5, 7])
    let expected = [1, 3, 5, 7].flatMap { ply in
        [gradeRequest(Array(history.prefix(ply - 1))), gradeRequest(Array(history.prefix(ply)))]
    }
    #expect(engine.requests == expected)
    for ply in [1, 3, 5, 7] {
        let v = session.verdicts[ply]
        #expect(v?.uci == history[ply - 1])
        #expect(v?.facts.fenBefore == Rules.fen(startFen: startFen, moves: Array(history.prefix(ply - 1))))
        #expect(v?.facts.fenAfter == Rules.fen(startFen: startFen, moves: Array(history.prefix(ply))))
    }
}

// MARK: - Take back

@MainActor @Test(arguments: [true, false])
func takeBackDiscardsInFlightGrade(engineHonorsCancellation: Bool) async {
    let engine = FakeEngine(botMoves: ["d7d5"], honorsCancellation: engineHonorsCancellation)
    engine.analysisGate.close()
    let session = makeSession(engine, mode: .training)
    session.start()

    #expect(session.userMove("e2e4"))
    #expect(session.phase == .grading)
    #expect(await eventually { engine.analysisGate.waiterCount == 1 })

    session.takeBack()
    #expect(session.fen == startFen)
    #expect(session.moves.isEmpty)
    #expect(session.sans.isEmpty)
    #expect(session.phase == .userTurn)

    engine.analysisGate.open()
    await settle()
    #expect(session.verdicts.isEmpty)
    #expect(session.fen == startFen)
    #expect(session.phase == .userTurn)
    #expect(engine.opponentCalls.isEmpty)

    // The queue is not wedged by the discarded job: a new move is graded under the new history.
    #expect(session.userMove("d2d4"))
    #expect(await eventually { session.moves.count == 2 && session.phase == .userTurn })
    #expect(session.verdicts.keys.sorted() == [1])
    #expect(session.verdicts[1]?.uci == "d2d4")
    #expect(engine.opponentCalls.map(\.moves) == [["d2d4"]])
}

@MainActor @Test func takeBackRemovesBotReplyAndItsVerdicts() async {
    let engine = FakeEngine(botMoves: ["e7e5", "b8c6"])
    let session = makeSession(engine, mode: .silent)
    session.start()
    #expect(session.userMove("e2e4"))
    #expect(await eventually { session.phase == .userTurn && session.moves.count == 2 })
    #expect(session.userMove("g1f3"))
    #expect(await eventually { session.moves.count == 4 && session.verdicts.count == 2 })

    session.takeBack()
    #expect(session.moves == ["e2e4", "e7e5"])
    #expect(session.sans == ["e4", "e5"])
    #expect(session.fen == Rules.fen(startFen: startFen, moves: ["e2e4", "e7e5"]))
    #expect(session.verdicts.keys.sorted() == [1])
    #expect(session.lastMove?.from == .e7 && session.lastMove?.to == .e5)
    #expect(session.tracker == {
        var t = PieceTracker(fen: startFen)
        t.apply("e2e4", fenBefore: startFen)
        t.apply("e7e5", fenBefore: Rules.fen(startFen: startFen, moves: ["e2e4"])!)
        return t
    }())
    #expect(session.phase == .userTurn)
}

// MARK: - Training interrupts

@MainActor @Test func trainingInterruptsOnMistakeNotInaccuracy() async {
    // Rating 800 thresholds: inaccuracy 120, mistake 250. Before +50 (White to move).
    // cpLoss 300: after = +250 for Black (side to move). cpLoss 130: after = +80 for Black.
    let mistakeEngine = FakeEngine(botMoves: ["e7e5"])
    mistakeEngine.script(gradeRequest([]), result(best: "d2d4", cp: 50))
    mistakeEngine.script(gradeRequest(["e2e4"]), result(best: "d7d5", cp: 250))
    let interrupted = makeSession(mistakeEngine, mode: .training)
    interrupted.start()
    #expect(interrupted.userMove("e2e4"))
    #expect(await eventually { interrupted.phase != .grading })
    guard case .interrupted(let verdict) = interrupted.phase else {
        Issue.record("expected .interrupted, got \(interrupted.phase)")
        return
    }
    #expect(verdict.cpLoss == 300)
    #expect(verdict.ply == 1)
    #expect(interrupted.verdicts[1] == verdict)
    await settle()
    #expect(mistakeEngine.opponentCalls.isEmpty)
    #expect(interrupted.userMove("d2d4") == false)

    interrupted.showBest()
    #expect(interrupted.bestArrow?.from == .d2 && interrupted.bestArrow?.to == .d4)
    interrupted.continueAfterInterrupt()
    #expect(await eventually { interrupted.moves == ["e2e4", "e7e5"] && interrupted.phase == .userTurn })
    #expect(interrupted.bestArrow == nil)

    let inaccuracyEngine = FakeEngine(botMoves: ["e7e5"])
    inaccuracyEngine.script(gradeRequest([]), result(best: "d2d4", cp: 50))
    inaccuracyEngine.script(gradeRequest(["e2e4"]), result(best: "d7d5", cp: 80))
    let badgeOnly = makeSession(inaccuracyEngine, mode: .training)
    badgeOnly.start()
    #expect(badgeOnly.userMove("e2e4"))
    #expect(await eventually { badgeOnly.moves.count == 2 && badgeOnly.phase == .userTurn })
    #expect(badgeOnly.verdicts[1]?.cpLoss == 130)
    #expect(inaccuracyEngine.opponentCalls.map(\.moves) == [["e2e4"]])
}

@MainActor @Test func trainingBotWaitsForTheGrade() async {
    let engine = FakeEngine(botMoves: ["e7e5"])
    engine.analysisGate.close()
    let session = makeSession(engine, mode: .training)
    session.start()
    #expect(session.userMove("e2e4"))
    #expect(await eventually { engine.analysisGate.waiterCount == 1 })
    await settle()
    #expect(session.phase == .grading)
    #expect(engine.opponentCalls.isEmpty)

    engine.analysisGate.open()
    #expect(await eventually { session.moves.count == 2 && session.phase == .userTurn })
    #expect(session.verdicts[1] != nil)
}

@MainActor @Test func silentModeNeverInterrupts() async {
    let engine = FakeEngine(botMoves: ["e7e5"])
    engine.script(gradeRequest([]), result(best: "d2d4", cp: 50))
    engine.script(gradeRequest(["e2e4"]), result(best: "d7d5", cp: 250))
    let session = makeSession(engine, mode: .silent)
    session.start()
    #expect(session.userMove("e2e4"))
    #expect(await eventually { session.verdicts[1] != nil && session.moves.count == 2 })
    await settle()
    #expect(session.verdicts[1]?.cpLoss == 300)
    #expect(session.phase == .userTurn)
    #expect(!isInterrupted(session.phase))
}

// MARK: - Moves

@MainActor @Test func promotionUciReachesEngine() async {
    let fen = "4k3/P7/8/8/8/8/7P/4K3 w - - 0 1"
    let engine = FakeEngine(botMoves: ["e8d7"])
    let session = makeSession(engine, mode: .silent, startFen: fen)
    session.start()
    #expect(session.userMove("a7a8n"))
    #expect(session.sans.last == "a8=N")
    #expect(await eventually { engine.requests.count == 2 && session.phase == .userTurn })
    #expect(engine.requests.last == gradeRequest(["a7a8n"], startFen: fen))
    #expect(engine.requests.last?.moves.last == "a7a8n")
    #expect(engine.opponentCalls.first == OpponentCall(startFen: fen, moves: ["a7a8n"], elo: 600))
    #expect(session.tracker.pieces.contains { $0.square == .a8 && $0.piece.kind == .knight })
}

@MainActor @Test(arguments: [PlayMode.training, .silent])
func noBotRequestAfterCheckmate(mode: PlayMode) async {
    let fen = "7k/8/6K1/8/8/8/8/Q7 w - - 0 1"  // Qa1-g7# (queen guarded by Kg6)
    let engine = FakeEngine(botMoves: ["h8g8"])
    let session = makeSession(engine, mode: mode, startFen: fen)
    session.start()
    #expect(session.userMove("a1g7"))
    #expect(session.phase == .over(.whiteWins, reason: .checkmate(winner: .white)))
    #expect(await eventually { session.verdicts[1] != nil })
    await settle()
    #expect(session.phase == .over(.whiteWins, reason: .checkmate(winner: .white)))
    #expect(engine.opponentCalls.isEmpty)
    #expect(session.userMove("h8g8") == false)
    #expect(session.snapshot().result == .whiteWins)
}

@MainActor @Test func threefoldFromCustomStartEndsGame() async {
    // The start position recurs for the third time after the bot's 4th move.
    let fen = "4k3/8/8/8/8/8/8/R3K3 w - - 0 1"
    let engine = FakeEngine(botMoves: ["e8e7", "e7e8", "e8e7", "e7e8"])
    let session = makeSession(engine, mode: .silent, startFen: fen)
    session.start()
    for uci in ["a1a2", "a2a1", "a1a2", "a2a1"] {
        #expect(await eventually { session.phase == .userTurn })
        #expect(session.userMove(uci))
    }
    #expect(await eventually { session.moves.count == 8 })
    #expect(session.phase == .over(.draw, reason: .threefold))
    #expect(engine.opponentCalls.count == 4)
}

@MainActor @Test func illegalOrOutOfTurnMoveRejected() async {
    let engine = FakeEngine(botMoves: ["e7e5"])
    engine.opponentGate.close()
    let session = makeSession(engine, mode: .silent)
    session.start()
    #expect(session.userMove("e2e5") == false)
    #expect(session.userMove("e7e5") == false)  // Black's pawn, White to move
    #expect(session.moves.isEmpty)

    #expect(session.userMove("e2e4"))
    #expect(session.phase == .botThinking)
    #expect(session.userMove("e7e5") == false)  // legal for the side to move, but it's the bot's turn
    #expect(session.moves == ["e2e4"])

    engine.opponentGate.open()
    #expect(await eventually { session.phase == .userTurn })
    #expect(session.moves == ["e2e4", "e7e5"])
}

// MARK: - Engine errors

@MainActor @Test func engineErrorIsRetryable() async {
    let engine = FakeEngine(botMoves: ["e2e4"])
    engine.failNextOpponentMove()
    let session = makeSession(engine, mode: .silent, userColor: .black)
    session.start()
    #expect(await eventually { session.phase == .engineError })
    #expect(session.moves.isEmpty)
    #expect(session.userMove("e7e5") == false)

    session.retry()
    #expect(await eventually { session.phase == .userTurn })
    #expect(session.moves == ["e2e4"])
    #expect(session.lastMove?.from == .e2 && session.lastMove?.to == .e4)
    #expect(engine.opponentCalls.count == 2)
}

@MainActor @Test func emptyBotMoveIsAnEngineError() async {
    let engine = FakeEngine(botMoves: [])
    let session = makeSession(engine, mode: .silent, userColor: .black)
    session.start()
    #expect(await eventually { session.phase == .engineError })
    #expect(session.moves.isEmpty)
}

// MARK: - Hint

@MainActor @Test func hintShowsEngineBestMove() async {
    let engine = FakeEngine()
    engine.script(AnalysisRequest(startFen: startFen, moves: [], depth: 16, multiPV: 1), result(best: "g1f3", cp: 30))
    let training = makeSession(engine, mode: .training)
    training.start()
    #expect(await training.hint())
    #expect(training.bestArrow?.from == .g1 && training.bestArrow?.to == .f3)
    #expect(engine.requests == [AnalysisRequest(startFen: startFen, moves: [], depth: 16, multiPV: 1)])

    let silentEngine = FakeEngine()
    let silent = makeSession(silentEngine, mode: .silent)
    silent.start()
    #expect(await silent.hint() == false)
    #expect(silent.bestArrow == nil)
    #expect(silentEngine.requests.isEmpty)
}

@MainActor @Test func hintReportsEngineFailure() async {
    let engine = FakeEngine()
    engine.failNextAnalyze()
    let session = makeSession(engine, mode: .training)
    session.start()
    #expect(await session.hint() == false)
    #expect(session.bestArrow == nil)
    #expect(session.phase == .userTurn)
    #expect(session.hasEngineError == false)
    #expect(engine.requests.count == 1)
}

// MARK: - Bot pacing

@MainActor @Test func botPacingPadsOnlyEarlySearches() async {
    #expect(thinkTimeMs(elo: 600, jitter: 0.5) == 450)

    // Search returns instantly: the move lands only once 450 ms have passed on the clock.
    let fastClock = ManualClock()
    let fast = makeSession(FakeEngine(botMoves: ["e2e4"]), userColor: .black, clock: fastClock)
    fast.start()
    #expect(fast.phase == .botThinking)
    #expect(await eventually { fastClock.sleeperCount == 1 })
    #expect(fastClock.sleepDurations == [.milliseconds(450)])
    fastClock.advance(by: .milliseconds(449))
    await settle()
    #expect(fast.moves.isEmpty)
    fastClock.advance(by: .milliseconds(1))
    #expect(await eventually { fast.moves == ["e2e4"] })
    #expect(fast.phase == .userTurn)

    // Search takes longer than the think time: no extra wait.
    let slowClock = ManualClock()
    let slowEngine = FakeEngine(botMoves: ["e2e4"])
    slowEngine.opponentGate.close()
    let slow = makeSession(slowEngine, userColor: .black, clock: slowClock)
    slow.start()
    #expect(await eventually { slowEngine.opponentGate.waiterCount == 1 })
    slowClock.advance(by: .milliseconds(600))
    slowEngine.opponentGate.open()
    #expect(await eventually { slow.moves == ["e2e4"] })
    #expect(slowClock.sleepDurations.allSatisfy { $0 <= .zero })
    #expect(slow.phase == .userTurn)
}

// MARK: - Resign and snapshot

@MainActor @Test func resignEndsGameAndSnapshotRecordsIt() async {
    let engine = FakeEngine(botMoves: ["e7e5"])
    let session = makeSession(engine, mode: .training)
    session.start()
    #expect(session.userMove("e2e4"))
    #expect(await eventually { session.phase == .userTurn && session.moves.count == 2 })

    session.resign()
    #expect(session.phase == .over(.blackWins, reason: nil))
    #expect(session.userMove("g1f3") == false)

    let snap = session.snapshot()
    #expect(snap.botId == "pip")
    #expect(snap.userColor == .white)
    #expect(snap.mode == .training)
    #expect(snap.startFen == startFen)
    #expect(snap.moves == ["e2e4", "e7e5"])
    #expect(snap.sans == ["e4", "e5"])
    #expect(snap.result == .blackWins)
    #expect(snap.verdicts.map(\.ply) == [1])
    #expect(snap.analysisVersion == 1)
    #expect(snap.playerRatingUsed == PlayerProfile.defaultRating)
}

@MainActor @Test func botMovesFirstWhenUserIsBlack() async {
    let engine = FakeEngine(botMoves: ["d2d4"])
    let session = makeSession(engine, mode: .training, userColor: .black)
    #expect(engine.opponentCalls.isEmpty)
    session.start()
    #expect(await eventually { session.phase == .userTurn })
    #expect(session.moves == ["d2d4"])
    #expect(session.sans == ["d4"])
    #expect(engine.opponentCalls == [OpponentCall(startFen: startFen, moves: [], elo: 600)])
}

// MARK: - Final snapshot and late engine errors

@MainActor private final class SnapshotBox {
    var snapshot: GameSnapshot?
}

/// Qa1-b1 Kh8-g8 Qb1-b8#: two user plies (1 and 3), the game ends on the user's move.
private let mateInTwoFen = "7k/8/6K1/8/8/8/8/Q7 w - - 0 1"

@MainActor @Test func finalSnapshotWaitsForQueuedGrades() async {
    let engine = FakeEngine(botMoves: ["h8g8"])
    engine.analysisGate.close()
    let session = makeSession(engine, mode: .silent, startFen: mateInTwoFen)
    session.start()
    #expect(session.userMove("a1b1"))
    #expect(await eventually { session.phase == .userTurn && session.moves.count == 2 })
    #expect(session.userMove("b1b8"))
    #expect(session.phase == .over(.whiteWins, reason: .checkmate(winner: .white)))
    #expect(session.pendingGradeCount == 2)
    #expect(session.snapshot().verdicts.isEmpty)

    let box = SnapshotBox()
    let waiter = Task { @MainActor in box.snapshot = await session.finalSnapshot() }
    await settle()
    #expect(box.snapshot == nil)  // still waiting: grades are held

    engine.analysisGate.open()
    await waiter.value
    #expect(box.snapshot?.verdicts.map(\.ply) == [1, 3])
    #expect(box.snapshot?.result == .whiteWins)
    #expect(session.pendingGradeCount == 0)
}

@MainActor @Test func gradeFailingAfterGameOverIsRetryable() async {
    let engine = FakeEngine()
    engine.failNextAnalyze()
    let session = makeSession(engine, mode: .silent, startFen: "7k/8/6K1/8/8/8/8/Q7 w - - 0 1")
    session.start()
    #expect(session.userMove("a1g7"))
    #expect(await eventually { session.hasEngineError })
    #expect(session.phase == .over(.whiteWins, reason: .checkmate(winner: .white)))
    #expect(session.verdicts.isEmpty)
    #expect(session.pendingGradeCount == 1)
    // With the queue stopped by an error, the final snapshot returns what exists instead of hanging.
    #expect(await session.finalSnapshot().verdicts.isEmpty)

    session.retry()
    #expect(session.hasEngineError == false)
    let snap = await session.finalSnapshot()
    #expect(snap.verdicts.map(\.ply) == [1])
    #expect(session.verdicts[1]?.uci == "a1g7")
    #expect(session.phase == .over(.whiteWins, reason: .checkmate(winner: .white)))
}

@MainActor @Test func retryAfterFailedGradeMidGame() async {
    let engine = FakeEngine(botMoves: ["e7e5"])
    engine.failNextAnalyze()
    let session = makeSession(engine, mode: .training)
    session.start()
    #expect(session.userMove("e2e4"))
    #expect(await eventually { session.phase == .engineError })
    #expect(session.hasEngineError)
    #expect(session.verdicts.isEmpty)
    #expect(engine.opponentCalls.isEmpty)

    session.retry()
    #expect(await eventually { session.moves.count == 2 && session.phase == .userTurn })
    #expect(session.verdicts[1]?.uci == "e2e4")
    #expect(session.hasEngineError == false)
    #expect(engine.opponentCalls.map(\.moves) == [["e2e4"]])
}

// MARK: - Take back after the end

@MainActor @Test func takeBackIsNoOpAfterResignButAllowedAfterMate() async {
    let engine = FakeEngine(botMoves: ["e7e5"])
    let resigned = makeSession(engine, mode: .silent)
    resigned.start()
    #expect(resigned.userMove("e2e4"))
    #expect(await eventually { resigned.phase == .userTurn && resigned.moves.count == 2 })
    resigned.resign()
    resigned.takeBack()
    #expect(resigned.moves == ["e2e4", "e7e5"])
    #expect(resigned.phase == .over(.blackWins, reason: nil))
    #expect(resigned.snapshot().result == .blackWins)

    let mated = makeSession(FakeEngine(), mode: .silent, startFen: "7k/8/6K1/8/8/8/8/Q7 w - - 0 1")
    mated.start()
    #expect(mated.userMove("a1g7"))
    #expect(mated.phase == .over(.whiteWins, reason: .checkmate(winner: .white)))
    mated.takeBack()
    #expect(mated.moves.isEmpty)
    #expect(mated.phase == .userTurn)
    #expect(mated.snapshot().result == .ongoing)
}
