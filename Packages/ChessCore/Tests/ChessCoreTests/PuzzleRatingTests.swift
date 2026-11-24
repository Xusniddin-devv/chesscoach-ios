import Testing
@testable import ChessCore

@Suite struct PuzzleRatingTests {
    @Test func evenPuzzleIsWorthHalfOfK() {
        #expect(PuzzleRating.delta(player: 1000, puzzle: 1000, solved: true) == 12)
        #expect(PuzzleRating.delta(player: 1000, puzzle: 1000, solved: false) == -12)
    }

    @Test func harderPuzzlesPayMoreAndCostLess() {
        #expect(PuzzleRating.delta(player: 800, puzzle: 1200, solved: true) > 12)
        #expect(PuzzleRating.delta(player: 800, puzzle: 1200, solved: false) > -12)
        #expect(PuzzleRating.updated(110, puzzle: 2400, solved: false) >= 100)
    }
}
