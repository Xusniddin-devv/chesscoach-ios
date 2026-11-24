import Testing
import SwiftData
import Foundation
import ChessCore
@testable import ChessCoach

@MainActor
struct FreeplayTests {
    private let container: ModelContainer

    init() throws {
        container = try ModelContainer(
            for: GameRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private var context: ModelContext { container.mainContext }

    private var records: [GameRecord] {
        (try? context.fetch(FetchDescriptor<GameRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }

    @discardableResult
    private func saveBotGame(bot: String = "pip", result: GameResult = .whiteWins, daysAgo: Double = 1) throws -> GameRecord {
        let snapshot = GameSnapshot(
            id: UUID(), date: Date.now.addingTimeInterval(-daysAgo * 86_400), botId: bot, userColor: .white,
            mode: .training, startFen: Rules.startFen, moves: [], sans: [], result: result, verdicts: [],
            analysisVersion: 1, playerRatingUsed: 800,
            analysis: GameAnalysis(depth: 14, verdicts: [], whiteWin: [], accuracyWhite: 80, accuracyBlack: 60))
        let record = try GameRecord(snapshot: snapshot)
        context.insert(record)
        try context.save()
        return record
    }

    /// A finished analysis-board line: White mates (fool's mate is Black's, so this is the
    /// scholar's mate), saved as freeplay. It must count nowhere.
    @discardableResult
    private func saveFreeplay(daysAgo: Double = 0) throws -> GameRecord {
        let model = FreeplayModel(engine: FakeEngine(botMoves: []), context: context)
        for uci in ["e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6", "h5f7"] { #expect(model.play(uci)) }
        let record = try #require(records.first { $0.snapshot?.isFreeplay == true })
        var snapshot = try #require(record.snapshot)
        snapshot.date = Date.now.addingTimeInterval(-daysAgo * 86_400)
        try record.update(snapshot)
        record.date = snapshot.date
        try context.save()
        return record
    }

    private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    // MARK: Saving

    @Test func freeplaySavesAnOwnerlessRecord() throws {
        let record = try saveFreeplay()
        let snapshot = try #require(record.snapshot)
        #expect(snapshot.source == GameSnapshot.Source.freeplay)
        #expect(snapshot.botId.isEmpty)
        #expect(snapshot.userColor == .white)
        #expect(snapshot.moves.count == 7)
        #expect(snapshot.result == .whiteWins)
        #expect(records.count == 1)
    }

    @Test func emptyBoardIsNotSaved() {
        let model = FreeplayModel(engine: FakeEngine(botMoves: []), context: context)
        model.save()
        #expect(records.isEmpty)
    }

    @Test func movesKeepUpdatingTheSameRecord() async throws {
        let engine = FakeEngine(botMoves: [])
        let model = FreeplayModel(engine: engine, context: context)
        model.play("e2e4")
        model.play("e7e5")
        #expect(records.count == 1)
        #expect(await eventually { model.grader.verdicts.count == 2 })
        model.save()
        let saved = try #require(records.first?.snapshot)
        #expect(saved.moves == ["e2e4", "e7e5"])
        #expect(saved.verdicts.map(\.ply) == [1, 2])

        // Reopened: the line and its grades come back without searching again.
        let before = engine.requests.count
        let reopened = FreeplayModel(engine: engine, record: records.first, context: context)
        #expect(reopened.moves == ["e2e4", "e7e5"])
        #expect(reopened.selectedPly == 2)
        #expect(reopened.grader.verdicts.count == 2)
        #expect(engine.requests.count == before)
    }

    @Test func playingAtAnEarlierPositionReplacesTheRest() {
        let model = FreeplayModel(engine: FakeEngine(botMoves: []), context: context)
        for uci in ["e2e4", "e7e5", "g1f3"] { model.play(uci) }
        model.step(-2)
        #expect(model.selectedPly == 1)
        // The line's own next move just steps forward.
        model.play("e7e5")
        #expect(model.moves.count == 3)
        #expect(model.selectedPly == 2)
        model.step(-1)
        model.play("c7c5")
        #expect(model.moves == ["e2e4", "c7c5"])
        #expect(model.sans == ["e4", "c5"])
    }

    @Test func takeBackDropsTheLastMove() {
        let model = FreeplayModel(engine: FakeEngine(botMoves: []), context: context)
        model.play("e2e4")
        model.play("e7e5")
        model.takeBack()
        #expect(model.moves == ["e2e4"])
        #expect(model.selectedPly == 1)
        #expect(records.first?.snapshot?.moves == ["e2e4"])
    }

    @Test func editorPositionStartsANewLine() throws {
        let model = FreeplayModel(engine: FakeEngine(botMoves: []), context: context)
        model.play("e2e4")
        let fen = "4k3/8/8/8/8/8/4P3/4K3 b - - 0 1"
        model.reset(to: fen)
        #expect(model.moves.isEmpty)
        #expect(model.startFen == fen)
        #expect(model.orientation == .black)
        #expect(model.statusText == "Black to move")
        model.play("e8d7")
        #expect(records.count == 2)
        #expect(records.contains { $0.snapshot?.startFen == fen })
    }

    @Test func deepSearchesAtDepth20() async {
        let engine = FakeEngine(botMoves: [])
        let model = FreeplayModel(engine: engine, context: context)
        model.refreshEval()
        #expect(await eventually { engine.requests.contains { $0.depth == 14 && $0.moves.isEmpty } })
        model.deep = true
        #expect(await eventually { engine.requests.contains { $0.depth == 20 && $0.moves.isEmpty } })
    }

    // MARK: Exclusion from stats, rating, ladder, Home

    @Test func profileIgnoresFreeplay() throws {
        try saveFreeplay()
        var model = ProfileModel(records: records)
        #expect(model.games.isEmpty)
        #expect(model.ratedGames.isEmpty)
        try saveBotGame()
        model = ProfileModel(records: records)
        #expect(model.games.count == 1)
        #expect(model.games.allSatisfy { !$0.snapshot.isFreeplay })
        #expect(model.finishedCount == 1)
    }

    @Test func ladderIgnoresFreeplayWins() throws {
        // The freeplay line is a White win with userColor White: it must not beat anyone.
        try saveFreeplay()
        let hub = EngineHub()
        let ladder = BotLadder(records: records, hub: hub)
        #expect(ladder.rungs.allSatisfy { !$0.isBeaten })
        try saveBotGame(bot: "pip")
        let after = BotLadder(records: records, hub: hub)
        #expect(after.rung(for: Bot.all[0]) == .beaten(wins: 1))
    }

    @Test func homeRecentListSkipsFreeplay() throws {
        for day in 1...6 { try saveBotGame(daysAgo: Double(day)) }
        try saveFreeplay(daysAgo: 0)
        let recent = HomeView.recentGames(records)
        #expect(recent.count == HomeView.recentCount)
        #expect(recent.allSatisfy { !$0.snapshot.isFreeplay })
        #expect(HomeView.latestFreeplay(records)?.snapshot.isFreeplay == true)
    }
}

@MainActor
struct GuessModelTests {
    private static let game = ["e2e4", "e7e5", "g1f3", "b8c6"]

    private func model(engine: FakeEngine = FakeEngine(botMoves: [])) async throws -> GuessModel {
        let analysis = try await GameAnalyzer(engine: engine).analyze(startFen: Rules.startFen, moves: Self.game)
        var fen = Rules.startFen
        var sans: [String] = []
        for uci in Self.game {
            let applied = Rules.apply(uci: uci, to: fen)!
            sans.append(applied.san)
            fen = applied.fenAfter
        }
        let snapshot = GameSnapshot(
            id: UUID(), date: .now, botId: "pip", userColor: .white, mode: .training, startFen: Rules.startFen,
            moves: Self.game, sans: sans, result: .ongoing, verdicts: [], analysisVersion: 1,
            playerRatingUsed: 800, analysis: analysis)
        return GuessModel(snapshot: snapshot, analysis: analysis, opponentName: "Pip",
                          userAvatar: RatingTier.pawn.avatarAsset, opponentAvatar: nil, engine: engine)
    }

    private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test func guessesTheChosenSideOnlyAndScores() async throws {
        let m = try await model()
        #expect(m.phase == .choosing)
        m.side = .black
        m.start()
        #expect(m.ply == 2)
        #expect(m.orientation == .black)
        #expect(m.displayedFen == Rules.fen(startFen: Rules.startFen, moves: ["e2e4"]))
        // The game's own move: scored from the saved analysis.
        #expect(m.guess("e7e5"))
        #expect(await eventually { m.isRevealed })
        #expect(m.revealed?.matchedGame == true)
        m.next()
        #expect(m.ply == 4)
        #expect(m.phase == .guessing)
        #expect(m.guess("g8f6"))
        #expect(await eventually { m.isRevealed })
        m.next()
        #expect(m.phase == .finished)
        #expect(m.results.map(\.ply) == [2, 4])
        #expect(m.total.max == 6)
    }

    @Test func illegalGuessIsRefusedAndSkipIsNotScored() async throws {
        let m = try await model()
        m.start()
        #expect(!m.guess("e2e5"))
        #expect(m.phase == .guessing)
        m.skip()
        #expect(m.ply == 3)
        #expect(m.results.isEmpty)
        m.finish()
        #expect(m.phase == .finished)
        m.restart()
        #expect(m.phase == .choosing)
    }

    @Test func engineFailureCanBeRetried() async throws {
        let engine = FakeEngine(botMoves: [])
        let m = try await model(engine: engine)
        m.start()
        engine.failNextAnalyses(1)
        // Not the game's move nor the saved best (the fake has none): searched.
        #expect(m.guess("d2d4"))
        #expect(await eventually { if case .failed = m.phase { true } else { false } })
        m.retry()
        #expect(await eventually { m.isRevealed })
        #expect(m.revealed?.guessSan == "d4")
    }
}
