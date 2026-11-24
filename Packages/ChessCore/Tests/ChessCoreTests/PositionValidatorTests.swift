import Foundation
import Testing
@testable import ChessCore

private func setup(_ fen: String) -> BoardSetup { BoardSetup(fen: fen)! }

@Test func startPositionIsValid() {
    #expect(PositionValidator.problems(.start).isEmpty)
    #expect(BoardSetup.start.fen == Rules.startFen)
}

@Test func emptyBoardNeedsBothKings() {
    #expect(PositionValidator.problems(.empty) == [.kingCount(.white, count: 0), .kingCount(.black, count: 0)])
    #expect(PositionProblem.kingCount(.white, count: 0).message == "Add a white king.")
}

@Test func twoKingsOfOneColourIsInvalid() {
    var board = setup("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
    board[Square("a1")] = SetupPiece(.white, .king)
    #expect(PositionValidator.problems(board) == [.kingCount(.white, count: 2)])
    #expect(PositionProblem.kingCount(.white, count: 2).message == "Only one white king, please.")
}

@Test func sideNotToMoveInCheckIsInvalid() {
    // White rook gives check to the black king, and it is White to move.
    let board = setup("4k3/8/8/8/8/8/8/R3K2r w - - 0 1")
    let checked = setup("4k3/8/8/8/8/8/8/4R1K1 w - - 0 1")
    #expect(PositionValidator.problems(checked) == [.sideNotToMoveInCheck(.black)])
    #expect(PositionProblem.sideNotToMoveInCheck(.black).message.contains("Black to move"))
    // The side to move may be in check (White is, by the h1 rook): fine.
    #expect(PositionValidator.problems(board).isEmpty)
    var fixed = checked
    fixed.sideToMove = .black
    #expect(PositionValidator.isValid(fixed))
}

@Test func pawnsOnBackRanksAreInvalid() {
    #expect(PositionValidator.problems(setup("4k2P/8/8/8/8/8/8/4K3 w - - 0 1")) == [.pawnOnBackRank])
    #expect(PositionValidator.problems(setup("4k3/8/8/8/8/8/8/p3K3 w - - 0 1")) == [.pawnOnBackRank])
}

@Test func moreThanSixteenPiecesIsInvalid() {
    var board = BoardSetup.start
    board[Square("e4")] = SetupPiece(.white, .queen)
    #expect(PositionValidator.problems(board) == [.tooManyPieces(.white)])
    var pawns = BoardSetup.start
    pawns[Square("e2")] = nil
    pawns[Square("d3")] = SetupPiece(.black, .pawn)
    pawns[Square("d7")] = SetupPiece(.black, .knight)
    pawns[Square("e5")] = SetupPiece(.black, .pawn)
    #expect(PositionValidator.problems(pawns).contains(.tooManyPieces(.black)))
}

@Test func moreThanEightPawnsIsInvalid() {
    var board = setup("4k3/8/8/8/8/8/PPPPPPPP/4K3 w - - 0 1")
    board[Square("e4")] = SetupPiece(.white, .pawn)
    #expect(PositionValidator.problems(board) == [.tooManyPawns(.white)])
}

@Test func castlingNeedsKingAndRookAtHome() {
    var board = BoardSetup.start
    #expect(board.availableCastling == Set(CastlingRight.allCases))
    board[Square("h1")] = nil
    board[Square("h3")] = SetupPiece(.white, .rook)
    #expect(!board.availableCastling.contains(.whiteKingside))
    #expect(board.fen.split(separator: " ")[2] == "Qkq")
    // The choice is kept: the rook back home turns the right on again.
    board[Square("h3")] = nil
    board[Square("h1")] = SetupPiece(.white, .rook)
    #expect(board.fen.split(separator: " ")[2] == "KQkq")
    board[Square("e8")] = nil
    board[Square("d8")] = SetupPiece(.black, .king)
    #expect(board.fen.split(separator: " ")[2] == "KQ")
}

@Test func fenRoundTripsAndKeepsSideToMove() {
    let fen = "r3k2r/pp3ppp/8/3q4/8/8/PP3PPP/R3K2R b Kq - 0 1"
    let board = setup(fen)
    #expect(board.fen == fen)
    #expect(board.sideToMove == .black)
    #expect(Position(fen: board.fen) != nil)
}
