import Testing
@testable import ChessCore

@Test func italianGame() {
    let moves = ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4"]
    let fen = Rules.fen(startFen: Rules.startFen, moves: moves)!
    #expect(OpeningBook.lookup(fen: fen)?.name.contains("Italian") == true)
}

@Test func frenchDefense() {
    let fen = Rules.fen(startFen: Rules.startFen, moves: ["e2e4", "e7e6"])!
    #expect(OpeningBook.lookup(fen: fen)?.name == "French Defense")
}

@Test func lookupIgnoresClocks() {
    let fen = Rules.fen(startFen: Rules.startFen, moves: ["e2e4", "e7e6"])!
    let parts = fen.split(separator: " ")
    let altered = parts.prefix(4).joined(separator: " ") + " 7 42"
    #expect(OpeningBook.lookup(fen: altered)?.name == "French Defense")
}

@Test func deepestKeepsLastKnownAfterLeavingBook() {
    let inBook = ["e2e4", "e7e6"]
    let expected = OpeningBook.deepest(startFen: Rules.startFen, moves: inBook)
    #expect(expected?.name == "French Defense")
    let out = inBook + ["a2a3", "a7a6", "h2h3", "h7h6", "b2b3", "b7b6"]
    #expect(OpeningBook.deepest(startFen: Rules.startFen, moves: out) == expected)
}

@Test func unknownStartFenReturnsNil() {
    #expect(OpeningBook.deepest(startFen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1", moves: ["e1e2"]) == nil)
    #expect(OpeningBook.lookup(fen: "garbage") == nil)
}
