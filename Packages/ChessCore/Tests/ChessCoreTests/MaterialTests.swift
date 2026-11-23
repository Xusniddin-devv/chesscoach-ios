import Testing
@testable import ChessCore

@Test func pieceValues() {
    #expect(pieceValue(.pawn) == 1)
    #expect(pieceValue(.knight) == 3)
    #expect(pieceValue(.bishop) == 3)
    #expect(pieceValue(.rook) == 5)
    #expect(pieceValue(.queen) == 9)
    #expect(pieceValue(.king) == 100)
}

@Test func evenQueenTradeIsNotASacrifice() {        // shipped web bug: Qxg3 labelled brilliant
    let before = "6k1/8/6q1/8/8/6Q1/5P2/6K1 b - - 0 1"
    let after = Rules.apply(uci: "g6g3", to: before)!.fenAfter
    #expect(isEnPrise(fenAfter: after, uci: "g6g3", mover: .black))
    #expect(capturedValue(fenBefore: before, uci: "g6g3") == 9)
    #expect(!isSacrifice(fenBefore: before, fenAfter: after, uci: "g6g3", mover: .black))
}
@Test func rookOfferedToPawnIsASacrifice() {
    let before = "4k3/8/3p4/8/8/8/8/2R1K3 w - - 0 1"
    let after = Rules.apply(uci: "c1c5", to: before)!.fenAfter
    #expect(isSacrifice(fenBefore: before, fenAfter: after, uci: "c1c5", mover: .white))
}
@Test func enPassantCapturedValueIsOne() {
    #expect(capturedValue(fenBefore: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2", uci: "e5d6") == 1)
}
