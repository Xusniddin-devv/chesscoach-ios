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

    // MARK: Helpers

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
