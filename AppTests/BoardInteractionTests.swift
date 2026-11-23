import Testing
import ChessCore
@testable import ChessCoach

struct BoardInteractionTests {
    static let start = Rules.startFen
    /// White pawn on e7, e8 empty, White to move.
    static let promotion = "7k/4P3/8/8/8/8/8/K7 w - - 0 1"

    @Test func tapOwnPieceSelectsItWithLegalTargets() {
        var board = BoardInteraction()
        #expect(board.tap(Square("e2"), fen: Self.start, side: .white)
            == .selected(Square("e2"), targets: [Square("e3"), Square("e4")]))
        #expect(board.selected == Square("e2"))
    }

    @Test func tapTargetPlaysTheMove() {
        var board = BoardInteraction()
        _ = board.tap(Square("e2"), fen: Self.start, side: .white)
        #expect(board.tap(Square("e4"), fen: Self.start, side: .white) == .move("e2e4"))
        #expect(board.selected == nil)
    }

    @Test func pawnToLastRankAsksForPromotion() {
        var board = BoardInteraction()
        _ = board.tap(Square("e7"), fen: Self.promotion, side: .white)
        #expect(board.tap(Square("e8"), fen: Self.promotion, side: .white)
            == .needsPromotion(from: Square("e7"), to: Square("e8")))
        #expect(board.selected == nil)
    }

    @Test func tapOpponentPieceWithNothingSelectedClears() {
        var board = BoardInteraction()
        #expect(board.tap(Square("e7"), fen: Self.start, side: .white) == .cleared)
        #expect(board.selected == nil)
    }

    @Test func tapAnotherOwnPieceReselects() {
        var board = BoardInteraction()
        _ = board.tap(Square("e2"), fen: Self.start, side: .white)
        #expect(board.tap(Square("g1"), fen: Self.start, side: .white)
            == .selected(Square("g1"), targets: [Square("f3"), Square("h3")]))
        #expect(board.selected == Square("g1"))
    }

    @Test func tapSelectedPieceAgainClears() {
        var board = BoardInteraction()
        _ = board.tap(Square("e2"), fen: Self.start, side: .white)
        #expect(board.tap(Square("e2"), fen: Self.start, side: .white) == .cleared)
    }

    @Test func tapNonTargetEmptySquareClears() {
        var board = BoardInteraction()
        _ = board.tap(Square("e2"), fen: Self.start, side: .white)
        #expect(board.tap(Square("e5"), fen: Self.start, side: .white) == .cleared)
        #expect(board.selected == nil)
    }

    @Test func nothingIsSelectableWhenItIsNotThatSidesTurn() {
        var board = BoardInteraction()
        #expect(board.tap(Square("e7"), fen: Self.start, side: .black) == .cleared)
    }

    @Test func dropOnTargetPlaysTheMove() {
        var board = BoardInteraction()
        #expect(board.drop(from: Square("g1"), to: Square("f3"), fen: Self.start, side: .white) == .move("g1f3"))
        #expect(board.selected == nil)
    }

    @Test func illegalDropKeepsThePieceSelected() {
        var board = BoardInteraction()
        #expect(board.drop(from: Square("g1"), to: Square("g3"), fen: Self.start, side: .white)
            == .selected(Square("g1"), targets: [Square("f3"), Square("h3")]))
    }

    @Test func dropPawnOnLastRankAsksForPromotion() {
        var board = BoardInteraction()
        #expect(board.drop(from: Square("e7"), to: Square("e8"), fen: Self.promotion, side: .white)
            == .needsPromotion(from: Square("e7"), to: Square("e8")))
    }
}
