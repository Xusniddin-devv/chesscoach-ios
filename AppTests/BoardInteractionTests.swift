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

    @Test func kingWithCastlingRightsCanCastleBothWays() {
        let fen = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"
        var board = BoardInteraction()
        guard case .selected(let from, let targets) = board.tap(Square("e1"), fen: fen, side: .white) else {
            Issue.record("king not selected"); return
        }
        #expect(from == Square("e1"))
        #expect(targets.contains(Square("g1")))
        #expect(targets.contains(Square("c1")))
        #expect(board.tap(Square("g1"), fen: fen, side: .white) == .move("e1g1"))
    }

    @Test func enPassantIsATargetAndPlays() {
        let fen = "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2"
        var board = BoardInteraction()
        guard case .selected(_, let targets) = board.tap(Square("e5"), fen: fen, side: .white) else {
            Issue.record("pawn not selected"); return
        }
        #expect(targets.contains(Square("d6")))
        #expect(board.tap(Square("d6"), fen: fen, side: .white) == .move("e5d6"))
    }

    @Test func captureOntoLastRankAsksForPromotion() {
        let fen = "3r3k/4P3/8/8/8/8/8/K7 w - - 0 1"
        var board = BoardInteraction()
        _ = board.tap(Square("e7"), fen: fen, side: .white)
        #expect(board.tap(Square("d8"), fen: fen, side: .white)
            == .needsPromotion(from: Square("e7"), to: Square("d8")))
    }

    @Test func dropWhenSideIsNotToMoveClears() {
        var board = BoardInteraction()
        #expect(board.drop(from: Square("e7"), to: Square("e5"), fen: Self.start, side: .black) == .cleared)
        #expect(board.selected == nil)
    }

    @Test func dropPawnOnLastRankAsksForPromotion() {
        var board = BoardInteraction()
        #expect(board.drop(from: Square("e7"), to: Square("e8"), fen: Self.promotion, side: .white)
            == .needsPromotion(from: Square("e7"), to: Square("e8")))
    }
}
