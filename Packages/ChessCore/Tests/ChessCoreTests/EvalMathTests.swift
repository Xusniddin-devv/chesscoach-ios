import Testing
@testable import ChessCore

@Test func toCpEncodesMate() {
    #expect(toCp(Score(cp: nil, mate: 3), sideToMove: .white) == 9970)
    #expect(toCp(Score(cp: nil, mate: -2), sideToMove: .white) == -9980)
    #expect(toCp(Score(cp: 40, mate: nil), sideToMove: .black) == -40)
}

/// `mate 0` is Stockfish's report for a side to move that is already checkmated (a deliberate
/// deviation from the web app, which mapped it to 0 cp — see web-rules.md "Score").
@Test func toCpMateZeroMeansSideToMoveIsMated() {
    #expect(toCp(Score(cp: nil, mate: 0), sideToMove: .black) == 10000)
    #expect(toCp(Score(cp: nil, mate: 0), sideToMove: .white) == -10000)
}

@Test func toCpStalemateCpZeroIsUnaffected() {
    #expect(toCp(Score(cp: 0, mate: nil), sideToMove: .black) == 0)
}

@Test func winPercentCurve() {
    #expect(winPercent(0) == 50)
    #expect(abs(winPercent(500) - 86.3) < 0.1)
    #expect(winPercent(5000) == winPercent(1500))
    #expect(abs(winPercent(1500) - 99.60) < 0.01)
}
