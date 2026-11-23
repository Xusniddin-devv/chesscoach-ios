import Testing
import SwiftData
import Foundation
import ChessCore
@testable import ChessCoach

@MainActor
struct PlayFlowTests {
    /// Scholar's mate through `PlayModel`, then the game-over "Done" save path.
    @Test func finishedGameIsSaved() async throws {
        let engine = FakeEngine(botMoves: ["e7e5", "b8c6", "g8f6"])
        let session = GameSession(bot: Bot.all[0], userColor: .white, mode: .training,
                                  engine: engine, clock: ImmediateClock())
        let model = PlayModel(session: session)
        model.start()

        for uci in ["e2e4", "f1c4", "d1h5"] {
            #expect(model.move(uci))
            #expect(await eventually { model.interactive })
        }
        #expect(model.move("h5f7"))
        #expect(session.phase == .over(.whiteWins, reason: .checkmate(winner: .white)))

        let container = try ModelContainer(
            for: GameRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        try await model.save(in: context)
        try await model.save(in: context)  // leaving twice (Done after Play again) saves once

        let records = try context.fetch(FetchDescriptor<GameRecord>())
        #expect(records.count == 1)
        let snapshot = try #require(records.first?.snapshot)
        #expect(snapshot.result.rawValue == "1-0")
        #expect(snapshot.verdicts.map(\.ply) == [1, 3, 5, 7])
    }

    private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}
