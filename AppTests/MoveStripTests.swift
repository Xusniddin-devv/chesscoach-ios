import Testing
import ChessCore
@testable import ChessCoach

/// The move strip's pure model: plies grouped into numbered moves.
struct MoveStripTests {
    private func items(_ sans: [String]) -> [MoveStripItem] {
        sans.enumerated().map { MoveStripItem(ply: $0.offset + 1, san: $0.element, moveClass: nil) }
    }

    @Test func pairsWhiteAndBlackUnderOneNumber() {
        let groups = MoveStripGroup.groups(items(["e4", "e5", "Nf3"]), startFen: Rules.startFen)
        #expect(groups.map(\.label) == ["1.", "2."])
        #expect(groups[0].white?.san == "e4")
        #expect(groups[0].black?.san == "e5")
        #expect(groups[1].white?.san == "Nf3")
        #expect(groups[1].black == nil)
    }

    /// A custom start with Black to move at move 5: the first group has only Black's move.
    @Test func blackToMoveStartsWithAnEllipsis() {
        let fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 5"
        let groups = MoveStripGroup.groups(items(["e5", "Nf3", "Nc6"]), startFen: fen)
        #expect(groups.map(\.label) == ["5…", "6."])
        #expect(groups[0].white == nil)
        #expect(groups[0].black?.ply == 1)
        #expect(groups[1].white?.ply == 2)
        #expect(groups[1].black?.ply == 3)
    }

    @Test func noMovesNoGroups() {
        #expect(MoveStripGroup.groups([], startFen: Rules.startFen).isEmpty)
    }

    @Test func itemsAreIdentifiedByPly() {
        let item = MoveStripItem(ply: 7, san: "Bc4", moveClass: .blunder)
        #expect(item.id == 7)
    }
}

/// Where the board stack goes: board as wide as allowed, the stack centred, and a bottom card
/// never covering the board.
struct BoardStackGeometryTests {
    /// iPhone 17 Pro-like region: the board takes the full width minus margins and the free
    /// space splits evenly above and below.
    @Test func tallRegionCentresAFullWidthBoard() {
        let g = BoardStackGeometry(width: 402, height: 718, margin: 8, above: 88, below: 72, covered: 0)
        #expect(g.side == 386)
        let freeBelow = 718 - (g.top + 88 + g.side + 72)
        #expect(abs(g.top - freeBelow) < 0.5)
    }

    /// A short region: the board shrinks to what is left and the stack starts at the top.
    @Test func shortRegionShrinksTheBoard() {
        let g = BoardStackGeometry(width: 402, height: 500, margin: 8, above: 88, below: 72, covered: 0)
        #expect(g.side == 340)
        #expect(g.top == 0)
    }

    /// A card overlapping the board by a little: the board shrinks, its top stays put.
    @Test func smallOverlapShrinksInPlace() {
        let free = BoardStackGeometry(width: 402, height: 718, margin: 8, above: 88, below: 72, covered: 0)
        let boardBottom = free.top + 88 + free.side
        let covered = 718 - boardBottom + 20  // 20 pt into the board
        let g = BoardStackGeometry(width: 402, height: 718, margin: 8, above: 88, below: 72, covered: covered)
        #expect(g.top == free.top)
        #expect(abs(g.side - (free.side - 20)) < 0.001)
    }

    /// A tall card on a small phone: the stack also moves up into its free space, and the
    /// board ends at the card.
    @Test func largeOverlapUsesTheFreeSpaceAboveToo() {
        let free = BoardStackGeometry(width: 375, height: 587, margin: 8, above: 88, below: 72, covered: 0)
        let g = BoardStackGeometry(width: 375, height: 587, margin: 8, above: 88, below: 72, covered: 186)
        #expect(g.top < free.top)
        #expect(g.top >= 0)
        #expect(g.side < free.side)
        #expect(abs(g.top + 88 + g.side - (587 - 186)) < 0.5)
    }

    @Test func cardBelowTheBoardChangesNothing() {
        let free = BoardStackGeometry(width: 402, height: 718, margin: 8, above: 88, below: 72, covered: 0)
        let g = BoardStackGeometry(width: 402, height: 718, margin: 8, above: 88, below: 72, covered: 60)
        #expect(g == free)
    }

    /// Review's card above the bar keeps the user bar clear: the board gives way earlier.
    @Test func keptContentUnderTheBoardStaysClear() {
        let g = BoardStackGeometry(width: 402, height: 718, margin: 8, above: 88, below: 72,
                                   covered: 200, kept: 44)
        #expect(g.top + 88 + g.side + 44 <= 718 - 200 + 0.001)
        let without = BoardStackGeometry(width: 402, height: 718, margin: 8, above: 88, below: 72, covered: 200)
        #expect(g.top + g.side < without.top + without.side)
    }

    /// Review: the stack moves up before the board shrinks.
    @Test func movesFirstKeepsTheBoardSize() {
        let free = BoardStackGeometry(width: 402, height: 718, margin: 8, above: 88, below: 72, covered: 0)
        let g = BoardStackGeometry(width: 402, height: 718, margin: 8, above: 88, below: 72,
                                   covered: 180, kept: 44, movesFirst: true)
        #expect(g.side == free.side)
        #expect(g.top < free.top)
        #expect(g.top + 88 + g.side + 44 <= 718 - 180 + 0.001)
    }
}
