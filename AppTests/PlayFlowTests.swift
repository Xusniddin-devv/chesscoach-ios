import Testing
import SwiftData
import Foundation
import ChessCore
@testable import ChessCoach

@MainActor
struct PlayFlowTests {
    /// Scholar's mate through `PlayModel`, then the game-over "Done" save path.
    @Test func finishedGameIsSaved() async throws {
        let (model, _) = try await scholarsMate()
        let context = try inMemoryContext()
        try await model.save(in: context)
        try await model.save(in: context)  // leaving twice (Done after Play again) saves once

        let records = try context.fetch(FetchDescriptor<GameRecord>())
        #expect(records.count == 1)
        let snapshot = try #require(records.first?.snapshot)
        #expect(snapshot.result.rawValue == "1-0")
        #expect(snapshot.verdicts.map(\.ply) == [1, 3, 5, 7])
    }

    @Test func failedSaveCanBeRetried() async throws {
        let (model, _) = try await scholarsMate()
        let context = try inMemoryContext()
        var attempts = 0
        model.persist = { snapshot, context in
            attempts += 1
            if attempts == 1 { throw FakeEngineError() }
            try PlayModel.insertRecord(snapshot, into: context)
        }

        await #expect(throws: FakeEngineError.self) { try await model.save(in: context) }
        #expect(!model.isSaved)
        try await model.save(in: context)
        #expect(model.isSaved)
        #expect(try context.fetch(FetchDescriptor<GameRecord>()).count == 1)
    }

    /// The last grade fails after the game ends: saving retries it and keeps every verdict.
    @Test func saveRetriesAStoppedGrade() async throws {
        let (model, _) = try await scholarsMate(failingFinalGrades: 1)
        #expect(model.session.hasEngineError)
        let context = try inMemoryContext()
        try await model.save(in: context)
        let snapshot = try #require(try context.fetch(FetchDescriptor<GameRecord>()).first?.snapshot)
        #expect(snapshot.verdicts.map(\.ply) == [1, 3, 5, 7])
    }

    /// At most two retries; then the partial game is saved (Plan 2 re-analyses it).
    @Test func saveGivesUpAfterTwoRetries() async throws {
        let (model, _) = try await scholarsMate(failingFinalGrades: 3)
        let context = try inMemoryContext()
        try await model.save(in: context)
        let records = try context.fetch(FetchDescriptor<GameRecord>())
        #expect(records.count == 1)
        #expect(records.first?.snapshot?.verdicts.map(\.ply) == [1, 3, 5])
    }

    // MARK: Hint

    /// The user moved while the hint was searching: the hint is dropped, which is not a failure.
    @Test func hintOvertakenByAMoveIsNotUnavailable() async throws {
        let engine = FakeEngine(botMoves: ["e7e5"])
        let model = PlayModel(session: GameSession(bot: Bot.all[0], userColor: .white, mode: .training,
                                                   engine: engine, clock: ImmediateClock()))
        model.start()
        engine.holdAnalyses()
        let hint = Task { await model.hint() }
        #expect(await eventually { engine.analysisCount == 1 })
        #expect(model.move("e2e4"))
        engine.releaseAnalyses()
        await hint.value
        #expect(!model.hintUnavailable)
        #expect(!model.isHinting)
    }

    @Test func failedHintIsUnavailable() async throws {
        let engine = FakeEngine(botMoves: [])
        let model = PlayModel(session: GameSession(bot: Bot.all[0], userColor: .white, mode: .training,
                                                   engine: engine, clock: ImmediateClock()))
        model.start()
        engine.failNextAnalyses(1)
        await model.hint()
        #expect(model.hintUnavailable)
    }

    // MARK: History viewing

    /// Tapping an earlier ply shows that position read-only; tapping the last ply is live.
    @Test func viewingHistoryIsReadOnly() async throws {
        let (model, _) = try await afterFirstReply()
        let afterE4 = try #require(Rules.fen(startFen: Rules.startFen, moves: ["e2e4"]))
        var tracker = PieceTracker(fen: Rules.startFen)
        tracker.apply("e2e4", fenBefore: Rules.startFen)

        model.select(ply: 1)
        #expect(model.viewedPly == 1)
        #expect(!model.interactive)
        #expect(model.displayedFen == afterE4)
        #expect(model.displayedTracker == tracker)
        #expect(model.displayedLastMove.map { [$0.from, $0.to] } == [Square("e2"), Square("e4")])

        model.select(ply: 2)
        #expect(model.viewedPly == nil)
        #expect(model.interactive)
        #expect(model.displayedFen == model.session.fen)
    }

    @Test func stepsStayInsideTheGame() async throws {
        let (model, _) = try await afterFirstReply()
        model.step(-1)
        #expect(model.viewedPly == 1)
        model.step(-5)
        #expect(model.viewedPly == 0)
        #expect(model.displayedFen == Rules.startFen)
        #expect(model.displayedLastMove == nil)
        model.step(1)
        #expect(model.viewedPly == 1)
        model.step(5)
        #expect(model.viewedPly == nil)
    }

    /// The bot replies while the user looks back: the view stays put and flags the new move;
    /// "Back to live" returns.
    @Test func botMoveWhileViewingFlagsNewMoves() async throws {
        let engine = FakeEngine(botMoves: ["e7e5"])
        let model = PlayModel(session: GameSession(bot: Bot.all[0], userColor: .white, mode: .training,
                                                   engine: engine, clock: ImmediateClock()))
        model.start()
        engine.holdAnalyses()  // the grade (and so the bot's reply) waits
        #expect(model.move("e2e4"))
        model.select(ply: 0)
        #expect(!model.hasNewMovesWhileViewing)
        engine.releaseAnalyses()
        #expect(await eventually { model.session.moves.count == 2 })

        #expect(model.viewedPly == 0)
        #expect(model.hasNewMovesWhileViewing)
        model.returnToLive()
        #expect(model.viewedPly == nil)
        #expect(!model.hasNewMovesWhileViewing)
        #expect(await eventually { model.interactive })
    }

    /// The user's own move always lands on the live board.
    @Test func userMoveReturnsToLive() async throws {
        let (model, _) = try await afterFirstReply()
        model.select(ply: 0)
        #expect(model.move("g1f3"))
        #expect(model.viewedPly == nil)
        #expect(model.session.moves.count >= 3)
    }

    // MARK: Move strip and status

    /// Training: the user's graded moves carry their class; the bot's never do.
    @Test func stripItemsCarryTheUsersGrades() async throws {
        let (model, _) = try await afterFirstReply()
        #expect(await eventually { model.session.verdicts[1] != nil })
        let items = model.stripItems
        #expect(items.map(\.san) == ["e4", "e5"])
        #expect(items.map(\.ply) == [1, 2])
        #expect(items[0].moveClass != nil)
        #expect(items[1].moveClass == nil)
    }

    /// Silent mode keeps grades out of sight until the game is over.
    @Test func silentStripHidesGradesDuringPlay() async throws {
        let engine = FakeEngine(botMoves: ["e7e5"])
        let model = PlayModel(session: GameSession(bot: Bot.all[0], userColor: .white, mode: .silent,
                                                   engine: engine, clock: ImmediateClock()))
        model.start()
        #expect(model.move("e2e4"))
        #expect(await eventually { model.session.verdicts[1] != nil && model.interactive })
        #expect(model.stripItems.allSatisfy { $0.moveClass == nil })
    }

    @Test func statusNamesTheOpening() async throws {
        let (model, _) = try await afterFirstReply()
        let opening = try #require(OpeningBook.deepest(startFen: Rules.startFen, moves: ["e2e4", "e7e5"]))
        #expect(model.statusText == opening.name)
    }

    // MARK: Helpers

    /// 1.e4 e5 in Training mode, back on the user's turn.
    private func afterFirstReply() async throws -> (PlayModel, FakeEngine) {
        let engine = FakeEngine(botMoves: ["e7e5", "b8c6", "g8f6"])
        let model = PlayModel(session: GameSession(bot: Bot.all[0], userColor: .white, mode: .training,
                                                   engine: engine, clock: ImmediateClock()))
        model.start()
        #expect(model.move("e2e4"))
        #expect(await eventually { model.interactive })
        return (model, engine)
    }

    /// 1.e4 e5 2.Bc4 Nc6 3.Qh5 Nf6 4.Qxf7#, Training mode. The final grade fails
    /// `failingFinalGrades` times; the test returns once that grade has stopped or finished.
    private func scholarsMate(failingFinalGrades: Int = 0) async throws -> (PlayModel, FakeEngine) {
        let engine = FakeEngine(botMoves: ["e7e5", "b8c6", "g8f6"])
        let session = GameSession(bot: Bot.all[0], userColor: .white, mode: .training,
                                  engine: engine, clock: ImmediateClock())
        let model = PlayModel(session: session)
        model.start()
        for uci in ["e2e4", "f1c4", "d1h5"] {
            #expect(model.move(uci))
            #expect(await eventually { model.interactive })
        }
        // Two analyses per graded move plus the prefetch after each bot move: let all of them
        // run before arming failures, so only the final grade fails.
        #expect(await eventually { engine.analysisCount == 9 })
        engine.failNextAnalyses(failingFinalGrades)
        #expect(model.move("h5f7"))
        #expect(session.phase == .over(.whiteWins, reason: .checkmate(winner: .white)))
        if failingFinalGrades > 0 {
            #expect(await eventually { session.hasEngineError })
        }
        return (model, engine)
    }

    private func inMemoryContext() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: GameRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}
