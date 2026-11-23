import Testing
import SwiftData
import Foundation
import ChessCore
@testable import ChessCoach

@MainActor
struct ReviewModelTests {
    private static let game = ["e2e4", "e7e5", "g1f3", "b8c6"]

    private func snapshot(moves: [String] = ReviewModelTests.game, analysis: GameAnalysis? = nil) -> GameSnapshot {
        var fen = Rules.startFen
        var sans: [String] = []
        for uci in moves {
            let applied = Rules.apply(uci: uci, to: fen)!
            sans.append(applied.san)
            fen = applied.fenAfter
        }
        return GameSnapshot(
            id: UUID(), date: .now, botId: "pip", userColor: .white, mode: .training,
            startFen: Rules.startFen, moves: moves, sans: sans, result: .whiteWins,
            verdicts: [], analysisVersion: 1, playerRatingUsed: 800, analysis: analysis)
    }

    /// A record saved in an in-memory store (the container is returned to keep it alive).
    private func stored(_ snapshot: GameSnapshot) throws -> (GameRecord, ModelContainer) {
        let container = try ModelContainer(
            for: GameRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let record = try GameRecord(snapshot: snapshot)
        container.mainContext.insert(record)
        try container.mainContext.save()
        return (record, container)
    }

    private func analysed() async throws -> (ReviewModel, FakeEngine, GameRecord, ModelContainer) {
        let (record, container) = try stored(snapshot())
        let engine = FakeEngine(botMoves: [])
        let model = ReviewModel(record: record, engine: engine)
        await model.start()
        try #require(model.analysis != nil)
        return (model, engine, record, container)
    }

    private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private func settle() async {
        for _ in 0..<300 { await Task.yield() }
    }

    // MARK: Analysis

    @Test func analysisRunsOnceAndIsStored() async throws {
        let (model, engine, record, container) = try await analysed()
        _ = container
        #expect(engine.requests.count == Self.game.count + 1)
        #expect(engine.requests.allSatisfy { $0.depth == 14 && $0.multiPV == 2 })
        let saved = try #require(record.snapshot)
        #expect(saved.analysis == model.analysis)
        #expect(saved.analysis?.verdicts.count == Self.game.count)
        #expect(saved.openingName != nil)
        #expect(saved.openingName == OpeningBook.deepest(startFen: Rules.startFen, moves: Self.game)?.name)

        // Reopening is instant: no engine work.
        let again = ReviewModel(record: record, engine: engine)
        #expect(!again.needsAnalysis)
        await again.start()
        #expect(engine.requests.count == Self.game.count + 1)
        #expect(again.analysis == model.analysis)
    }

    @Test func outdatedAnalysisIsRedone() throws {
        let old = GameAnalysis(version: GameAnalysis.currentVersion - 1, depth: 14, verdicts: [],
                               whiteWin: [50], accuracyWhite: 100, accuracyBlack: 100)
        let (record, container) = try stored(snapshot(moves: [], analysis: old))
        _ = container
        #expect(ReviewModel(record: record, engine: FakeEngine(botMoves: [])).needsAnalysis)
    }

    @Test func cancelLeavesTheRecordUnchanged() async throws {
        let (record, container) = try stored(snapshot())
        _ = container
        let before = record.snapshotData
        let engine = FakeEngine(botMoves: [])
        engine.holdAnalyses()
        let model = ReviewModel(record: record, engine: engine)
        let run = Task { await model.start() }
        #expect(await eventually { engine.analysisCount == 1 })
        #expect(model.isAnalysing)

        model.cancel()
        engine.releaseAnalyses()
        await run.value
        await settle()
        #expect(record.snapshotData == before)
        #expect(model.analysis == nil)
        #expect(!model.isAnalysing)
        #expect(!model.analysisFailed)
        #expect(engine.analysisCount < Self.game.count + 1)
    }

    /// Leaving the screen cancels the view's task, which must stop the run the same way.
    @Test func cancelledTaskStoresNothing() async throws {
        let (record, container) = try stored(snapshot())
        _ = container
        let before = record.snapshotData
        let engine = FakeEngine(botMoves: [])
        engine.holdAnalyses()
        let model = ReviewModel(record: record, engine: engine)
        let run = Task { await model.start() }
        #expect(await eventually { engine.analysisCount == 1 })
        run.cancel()
        engine.releaseAnalyses()
        await run.value
        #expect(record.snapshotData == before)
        #expect(model.analysis == nil)
        #expect(!model.isAnalysing)
    }

    @Test func engineErrorStopsAndRetryFinishes() async throws {
        let (record, container) = try stored(snapshot())
        _ = container
        let engine = FakeEngine(botMoves: [])
        engine.failNextAnalyses(1)
        let model = ReviewModel(record: record, engine: engine)
        await model.start()
        #expect(model.analysisFailed)
        #expect(model.statusText == "Analysis stopped")
        #expect(record.snapshot?.analysis == nil)

        await model.start()
        #expect(!model.analysisFailed)
        #expect(record.snapshot?.analysis != nil)
    }

    @Test func noAnalysisWhileAGameIsLive() async throws {
        let (record, container) = try stored(snapshot())
        _ = container
        let engine = FakeEngine(botMoves: [])
        let model = ReviewModel(record: record, engine: engine, analysisAllowed: false)
        await model.start()
        #expect(engine.analysisCount == 0)
        #expect(model.analysis == nil)
        #expect(!model.interactive)
        #expect(!model.playBranchMove("e2e4"))
    }

    // MARK: Stepping

    @Test func selectAndStepStayInBounds() async throws {
        let (model, _, _, container) = try await analysed()
        _ = container
        #expect(model.selectedPly == 0)
        #expect(!model.canStepBack)
        model.step(-1)
        #expect(model.selectedPly == 0)
        model.select(ply: 99)
        #expect(model.selectedPly == Self.game.count)
        #expect(!model.canStepForward)
        model.step(1)
        #expect(model.selectedPly == Self.game.count)
        model.step(-1)
        #expect(model.selectedPly == 3)
        #expect(model.displayedLastMove.map { [$0.from.notation, $0.to.notation] } == ["g1", "f3"])
        #expect(model.selectedVerdict?.ply == 3)
        model.select(ply: -5)
        #expect(model.selectedPly == 0)
        #expect(model.displayedFen == Rules.startFen)
    }

    // MARK: Branches

    @Test func theGamesOwnMoveJustStepsForward() async throws {
        let (model, _, _, container) = try await analysed()
        _ = container
        model.select(ply: 2)
        #expect(model.playBranchMove("g1f3"))
        #expect(model.branch == nil)
        #expect(model.selectedPly == 3)
    }

    @Test func branchMovesAreGradedWithTheirOwnHistory() async throws {
        let (model, engine, record, container) = try await analysed()
        _ = container
        let stored = record.snapshotData
        let analysed = engine.requests.count
        model.select(ply: 2)
        #expect(model.playBranchMove("f1c4"))
        #expect(model.playBranchMove("g8f6"))
        #expect(model.branch?.map(\.ply) == [3, 4])
        #expect(model.branch?.map(\.san) == ["Bc4", "Nf6"])
        #expect(model.selectedPly == 4)
        #expect(model.currentLine == ["e2e4", "e7e5", "f1c4", "g8f6"])
        #expect(await eventually { model.grader.verdicts.count == 2 })

        let prefix = Array(Self.game.prefix(2))
        let expected = [prefix, prefix + ["f1c4"], prefix + ["f1c4"], prefix + ["f1c4", "g8f6"]].map {
            AnalysisRequest(startFen: Rules.startFen, moves: $0, depth: 14, multiPV: 2)
        }
        #expect(Array(engine.requests.dropFirst(analysed)) == expected)
        #expect(model.verdict(atPly: 3)?.san == "Bc4")
        #expect(model.verdict(atPly: 2)?.san == "e5")  // the game's own ply, from the analysis
        #expect(model.stripItems.map(\.san) == ["e4", "e5", "Bc4", "Nf6"])
        #expect(model.stripItems.map(\.isBranch) == [false, false, true, true])
        #expect(record.snapshotData == stored)  // branches are never saved
    }

    @Test func aMoveInsideABranchReplacesTheRestOfIt() async throws {
        let (model, _, _, container) = try await analysed()
        _ = container
        model.select(ply: 2)
        model.playBranchMove("f1c4")
        model.playBranchMove("g8f6")
        #expect(await eventually { model.grader.verdicts.count == 2 })
        model.step(-1)
        #expect(model.playBranchMove("b8c6"))
        #expect(model.branch?.map(\.san) == ["Bc4", "Nc6"])
        #expect(model.grader.verdicts[4] == nil)
        #expect(await eventually { model.grader.verdicts[4]?.san == "Nc6" })
    }

    @Test func exitBranchDiscardsLateGrades() async throws {
        let (model, engine, _, container) = try await analysed()
        _ = container
        engine.holdAnalyses()
        model.select(ply: 2)
        model.playBranchMove("f1c4")
        #expect(model.isCheckingSelected)
        #expect(await eventually { engine.analysisCount == Self.game.count + 2 })

        model.exitBranch()
        engine.releaseAnalyses()
        await settle()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.branch == nil)
        #expect(model.selectedPly == 2)
        #expect(model.grader.verdicts.isEmpty)
        #expect(model.grader.pendingCount == 0)
        #expect(model.stripItems.count == Self.game.count)
        #expect(model.stripItems.allSatisfy { !$0.isBranch })
    }

    // MARK: Display

    @Test func commentsSpeakToTheUserAndNameTheBot() async throws {
        let (model, _, _, container) = try await analysed()
        _ = container
        var verdict = try #require(model.gameVerdict(atPly: 1))
        verdict.classification = .best
        #expect(ReviewModel.comment(on: verdict, byUser: true, botName: "Pip", wording: .words) == "e4 is the best move.")
        verdict.classification = .inaccuracy
        verdict.bestSan = "d4"
        #expect(ReviewModel.comment(on: verdict, byUser: false, botName: "Pip", wording: .words)
                == "Pip played e4, an inaccuracy. Better was d4.")
        #expect(ReviewModel.comment(on: verdict, byUser: true, botName: "Pip", wording: .words)
                == explain(verdict, wording: .words))
        // Every selected move with a grade has a comment; the start position has none.
        model.select(ply: 0)
        #expect(model.explanation == nil)
        model.select(ply: 1)
        #expect(model.explanation != nil)
    }

    @Test func evalFollowsTheAnalysis() {
        #expect(abs(ReviewModel.cp(fromWhiteWin: 50)) < 0.001)
        #expect(abs(winPercent(ReviewModel.cp(fromWhiteWin: 73)) - 73) < 0.001)
        #expect(ReviewModel.cp(fromWhiteWin: 10) < 0)
    }

    @Test func unreadableRecordShowsNothingAndNeverAnalyses() async throws {
        let (record, container) = try stored(snapshot())
        _ = container
        record.snapshotData = Data("{}".utf8)
        let engine = FakeEngine(botMoves: [])
        let model = ReviewModel(record: record, engine: engine)
        await model.start()
        #expect(engine.analysisCount == 0)
        #expect(!model.isReadable)
        #expect(record.snapshotData == Data("{}".utf8))
    }
}
