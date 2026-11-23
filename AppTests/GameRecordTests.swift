import Testing
import SwiftData
import Foundation
import ChessCore
@testable import ChessCoach

@MainActor
struct GameRecordTests {
    @Test func snapshotRoundTripInMemoryStore() throws {
        let original = GameSnapshot(
            id: UUID(), date: Date(timeIntervalSince1970: 1_700_000_000), botId: "pip",
            userColor: .white, mode: .training, startFen: Rules.startFen,
            moves: ["e2e4", "e7e5"], sans: ["e4", "e5"], result: .ongoing,
            verdicts: [], analysisVersion: 1, playerRatingUsed: 800)
        let container = try ModelContainer(
            for: GameRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.insert(try GameRecord(snapshot: original))
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<GameRecord>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.snapshot == original)
    }
}
