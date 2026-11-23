import Testing
@testable import ChessCore

@Test func trackerCastlingEnPassantPromotion() {
    var t = PieceTracker(fen: "4k3/P7/8/3pP3/8/8/8/4K2R w K d6 0 1")
    let rookId = t.pieces.first { $0.square == .h1 }!.id
    t.apply("e1g1", fenBefore: "4k3/P7/8/3pP3/8/8/8/4K2R w K d6 0 1")
    #expect(t.pieces.first { $0.id == rookId }!.square == .f1)
    var u = PieceTracker(fen: "4k3/P7/8/3pP3/8/8/8/4K2R w K d6 0 1")
    u.apply("e5d6", fenBefore: "4k3/P7/8/3pP3/8/8/8/4K2R w K d6 0 1")
    #expect(!u.pieces.contains { $0.square == .d5 })
    var v = PieceTracker(fen: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"); let promoId = v.pieces.first { $0.square == .a7 }!.id
    v.apply("a7a8q", fenBefore: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
    #expect(v.pieces.first { $0.id == promoId }?.piece.kind == .queen && v.pieces.first { $0.id == promoId }?.square == .a8)
}

@Test func trackerIllegalMoveLeavesUnchanged() {
    let fen = "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"
    var t = PieceTracker(fen: fen)
    let before = t
    t.apply("e1e5", fenBefore: fen)
    #expect(t == before)
}

@Test func trackerCaptureRemovesCapturedId() {
    let fen = "4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1"
    var t = PieceTracker(fen: fen)
    let pawnId = t.pieces.first { $0.square == .e4 }!.id
    let victimId = t.pieces.first { $0.square == .d5 }!.id
    t.apply("e4d5", fenBefore: fen)
    #expect(t.pieces.first { $0.id == pawnId }?.square == .d5)
    #expect(!t.pieces.contains { $0.id == victimId })
    #expect(t.pieces.count == 3)
}
