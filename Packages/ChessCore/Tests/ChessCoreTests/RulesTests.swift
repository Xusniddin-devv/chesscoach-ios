import Testing
@testable import ChessCore

@Test func pawnAndKnightAttackers() {
    let p = Position(fen: "4k3/8/8/3p4/8/2N5/8/4K3 w - - 0 1")!
    #expect(Set(Rules.attackers(of: .d5, by: .white, in: p)) == [.c3])
    #expect(Rules.attackers(of: .e4, by: .black, in: p) == [.d5])
}
@Test func slidingAttackersAreBlocked() {
    let p = Position(fen: "4k3/8/8/8/R2p3q/8/8/4K3 w - - 0 1")!
    #expect(Rules.attackers(of: .h4, by: .white, in: p).isEmpty)
}
@Test func applyHandlesPromotionCastleEnPassant() {
    #expect(Rules.apply(uci: "a7a8n", to: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1")?.san == "a8=N")
    #expect(Rules.apply(uci: "e1g1", to: "4k3/8/8/8/8/8/8/4K2R w K - 0 1")?.isCastle == true)
    let ep = Rules.apply(uci: "e5d6", to: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2")
    #expect(ep?.isEnPassant == true && ep?.isCapture == true)
    #expect(Rules.apply(uci: "e2e5", to: Rules.startFen) == nil)
}
@Test func legalMoveCountAndStates() {
    #expect(Rules.legalMoveCount(fen: Rules.startFen) == 20)
    #expect(Rules.state(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1", history: []) == .stalemate)
    #expect(Rules.state(fen: "7k/6Q1/6K1/8/8/8/8/8 b - - 0 1", history: []) == .checkmate(winner: .white))
}
@Test func threefoldFromHistory() {
    let moves = ["g1f3","g8f6","f3g1","f6g8","g1f3","g8f6","f3g1","f6g8"]
    let fen = Rules.fen(startFen: Rules.startFen, moves: moves)!
    #expect(Rules.state(fen: fen, history: moves) == .threefold)
}
@Test func threefoldFromCustomStart() {
    let start = "4k3/8/8/8/8/8/8/R3K3 w - - 0 1"
    let moves = ["a1a2","e8d8","a2a1","d8e8","a1a2","e8d8","a2a1","d8e8"]
    let fen = Rules.fen(startFen: start, moves: moves)!
    #expect(Rules.state(fen: fen, history: moves, startFen: start) == .threefold)
}
