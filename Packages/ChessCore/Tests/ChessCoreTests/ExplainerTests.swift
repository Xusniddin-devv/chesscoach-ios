import Testing
@testable import ChessCore

private let before = "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"

private func verdict(motifs: [Motif], cpLoss: Int, bestUci: String = "f1c4",
                     cls: MoveClass = .blunder) -> Verdict {
    let facts = MoveFacts(fenBefore: before, fenAfter: before, playedUci: "f3g5", playedSan: "Ng5",
                          bestUci: bestUci, bestPv: [], bestReplyUci: "", cpLoss: cpLoss,
                          evalAfterWhiteCp: 0, mateForMoverBefore: nil, mateAgainstMoverAfter: nil,
                          moveNumber: 3, mover: .white)
    return Verdict(ply: 5, san: "Ng5", uci: "f3g5", mover: .white, classification: cls, cpLoss: cpLoss,
                   winDrop: 0, evalWhiteCp: 0, mateBefore: nil, mateAfter: nil, bestMove: bestUci,
                   bestSan: "Bc4", bestLineSan: [], motifs: motifs, facts: facts)
}

@Test func explanationInWords() {
    let v = verdict(motifs: [.hangingPiece], cpLoss: 320)
    #expect(explain(v, wording: .words) == "Ng5 is a blunder: your piece can simply be captured there. Better was Bc4 - your bishop moves from f1 to c4.")
    #expect(explain(v, wording: .notation) == "Ng5 is a blunder: your piece can simply be captured there. Better was Bc4.")
}

@Test func explanationWithoutMotifUsesPawnUnits() {
    let v = verdict(motifs: [], cpLoss: 130)
    #expect(explain(v, wording: .words) == "Ng5 is a blunder: it gives up about 1.3 pawns of advantage (chess engines measure positions in pawn-units: +1.0 means being one pawn ahead). Better was Bc4 - your bishop moves from f1 to c4.")
    #expect(explain(verdict(motifs: [], cpLoss: 130), wording: .notation).contains("about 1.3 pawns of advantage. Better"))
}

@Test func captureWording() {
    let b = "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"
    var v = verdict(motifs: [.missedCapture], cpLoss: 200, bestUci: "e4d5")
    v.facts.fenBefore = b
    #expect(explain(v, wording: .words).hasSuffix("Better was exd5 - your pawn on e4 takes the pawn on d5."))
}
