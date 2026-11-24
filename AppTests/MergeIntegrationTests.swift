import Testing
import SwiftData
import Foundation
import ChessCore
@testable import ChessCoach

/// What the settings-paywall merge has to keep true across both branches.
@MainActor
struct MergeIntegrationTests {
    private func snapshot(source: String?, opponentRating: Int? = nil, result: GameResult = .whiteWins) -> GameSnapshot {
        GameSnapshot(id: UUID(), date: .now, botId: source ?? "ron", userColor: .white, mode: .silent,
                     startFen: Rules.startFen, moves: ["e2e4"], sans: ["e4"], result: result, verdicts: [],
                     analysisVersion: 1, playerRatingUsed: 800, source: source, opponentName: source == nil ? nil : "opp",
                     opponentRating: opponentRating)
    }

    @Test func profileCountsImportsButNeverFreeplay() throws {
        let container = try ModelContainer(for: ModelStore.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        for s in [snapshot(source: nil), snapshot(source: GameSnapshot.Source.chesscom, opponentRating: 1500),
                  snapshot(source: GameSnapshot.Source.freeplay)] {
            ctx.insert(try GameRecord(snapshot: s))
        }
        try ctx.save()
        let records = try ctx.fetch(FetchDescriptor<GameRecord>())
        let model = ProfileModel(records: records)
        #expect(model.games.count == 2)
        #expect(!model.games.contains { $0.snapshot.isFreeplay })
        #expect(model.games.contains { $0.botName == "opp" })
        #expect(HomeView.recentGames(records).count == 2)
    }

    @Test func coachTextMarksSquaresAndTheMove() {
        #expect(CoachText.marked("Your knight on g5 was left hanging.") == "Your knight on [g5] was left hanging.")
        // Squares inside a move stay text; the move itself turns bold.
        #expect(CoachText.marked("Nf3 is the best move.", san: "Nf3") == "**Nf3** is the best move.")
        #expect(CoachText.marked("exd5 takes back on d5.", san: "exd5") == "**exd5** takes back on [d5].")
        // Already marked text is left alone.
        #expect(CoachText.marked("Lands on [c4].") == "Lands on [c4].")
    }

    @Test func fixItIsBuiltFromOwnBlundersFirst() {
        let puzzles = BlunderPuzzles.fixIt(.hangingPiece, snapshots: [], rating: 800, count: 5)
        #expect(puzzles.count == 5)  // no own games: all from the bank, on the habit's themes
    }
}
