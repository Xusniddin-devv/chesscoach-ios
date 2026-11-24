import Testing
@testable import ChessCore

private func verdict(ply: Int, cls: MoveClass, winDrop: Double) -> Verdict {
    let fen = Rules.startFen
    let facts = MoveFacts(fenBefore: fen, fenAfter: fen, playedUci: "e2e4", playedSan: "e4",
                          bestUci: "e2e4", bestPv: [], bestReplyUci: "", cpLoss: 0,
                          evalAfterWhiteCp: 0, mateForMoverBefore: nil, mateAgainstMoverAfter: nil,
                          moveNumber: 1, mover: .white)
    return Verdict(ply: ply, san: "e4", uci: "e2e4", mover: ply % 2 == 1 ? .white : .black,
                   classification: cls, cpLoss: 0, winDrop: winDrop, evalWhiteCp: 0, mateBefore: nil,
                   mateAfter: nil, bestMove: "e2e4", bestSan: "e4", bestLineSan: [], motifs: [], facts: facts)
}

@Test func classCountsKeepOrderAndSkipZeros() {
    let counts = moveClassCounts([
        verdict(ply: 1, cls: .blunder, winDrop: 30), verdict(ply: 3, cls: .best, winDrop: 0),
        verdict(ply: 5, cls: .best, winDrop: 0), verdict(ply: 7, cls: .brilliant, winDrop: 0),
    ])
    #expect(counts.map(\.moveClass) == [.brilliant, .best, .blunder])
    #expect(counts.map(\.count) == [1, 2, 1])
}

@Test func keyMomentIsTheBiggestDrop() {
    let verdicts = [verdict(ply: 4, cls: .mistake, winDrop: 18), verdict(ply: 9, cls: .blunder, winDrop: 41),
                    verdict(ply: 12, cls: .blunder, winDrop: 41)]
    #expect(keyMoment(verdicts)?.ply == 9)
    #expect(keyMoment([verdict(ply: 2, cls: .inaccuracy, winDrop: 6)]) == nil)
}
