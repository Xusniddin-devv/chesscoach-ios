import Testing
@testable import ChessCore

private let italianBefore = "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"

private func facts(_ before: String, _ after: String? = nil, uci: String, san: String, best: String,
                   reply: String = "", cpLoss: Int, mover: Piece.Color = .white,
                   mateFor: Int? = nil, mateAgainst: Int? = nil, moveNumber: Int = 20) -> MoveFacts {
    MoveFacts(fenBefore: before, fenAfter: after ?? Rules.apply(uci: uci, to: before)!.fenAfter,
              playedUci: uci, playedSan: san, bestUci: best, bestPv: [best], bestReplyUci: reply,
              cpLoss: cpLoss, evalAfterWhiteCp: 0, mateForMoverBefore: mateFor,
              mateAgainstMoverAfter: mateAgainst, moveNumber: moveNumber, mover: mover)
}

@Test func hangingKnightAfterNg5() {
    let f = facts(italianBefore, uci: "f3g5", san: "Ng5", best: "f1c4", reply: "d8g5", cpLoss: 320, moveNumber: 3)
    #expect(detectMotifs(f) == [.hangingPiece])
}

@Test func allowedMateComesFirst() {
    let f = facts(italianBefore, uci: "f3g5", san: "Ng5", best: "f1c4", cpLoss: 320, mateAgainst: 2, moveNumber: 3)
    #expect(detectMotifs(f).first == .allowedMate)
    #expect(detectMotifs(f).contains(.hangingPiece))
}

@Test func missedMateNeedsLossOver200() {
    let low = facts(italianBefore, uci: "f1c4", san: "Bc4", best: "f3g5", cpLoss: 150, mateFor: 3)
    let high = facts(italianBefore, uci: "f1c4", san: "Bc4", best: "f3g5", cpLoss: 250, mateFor: 3)
    #expect(!detectMotifs(low).contains(.missedMate))
    #expect(detectMotifs(high).contains(.missedMate))
}

@Test func allowedForkCountsTwoValuablePieces() throws {
    // Black knight d4 -> e2+ forks Kg1 and Rc1.
    let after = "7k/8/8/8/3n4/8/P7/2R3K1 b - - 0 1"
    #expect(Rules.apply(uci: "d4e2", to: after) != nil)
    let f = facts("7k/8/8/8/3n4/8/P7/2R3K1 w - - 0 1", after, uci: "a2a3", san: "a3", best: "c1c8",
                  reply: "d4e2", cpLoss: 300)
    #expect(detectMotifs(f).contains(.allowedFork))
    var weak = f; weak.cpLoss = 149
    #expect(!detectMotifs(weak).contains(.allowedFork))
    var none = f; none.bestReplyUci = ""
    #expect(!detectMotifs(none).contains(.allowedFork))
}

@Test func missedCaptureWhenBestIsCapture() {
    let before = "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"
    #expect(Rules.apply(uci: "e4d5", to: before)?.isCapture == true)
    let f = facts(before, uci: "a2a3", san: "a3", best: "e4d5", cpLoss: 100)
    #expect(detectMotifs(f).contains(.missedCapture))
    var low = f; low.cpLoss = 99
    #expect(!detectMotifs(low).contains(.missedCapture))
}

@Test func openingPrincipleEarlyQueen() {
    let before = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"
    let f = facts(before, uci: "d1h5", san: "Qh5", best: "g1f3", cpLoss: 60, moveNumber: 3)
    #expect(detectMotifs(f).contains(.openingPrinciple))
    var late = f; late.moveNumber = 6
    #expect(!detectMotifs(late).contains(.openingPrinciple))
}

@Test func missedMateBoundaryAndSuppression() {
    func f(_ loss: Int, against: Int? = nil) -> MoveFacts {
        facts(italianBefore, uci: "f1c4", san: "Bc4", best: "f3g5", cpLoss: loss, mateFor: 3, mateAgainst: against)
    }
    #expect(!detectMotifs(f(200)).contains(.missedMate))
    #expect(detectMotifs(f(201)).contains(.missedMate))
    let both = detectMotifs(f(400, against: 2))
    #expect(both.contains(.allowedMate))
    #expect(!both.contains(.missedMate))
}

@Test func allowedForkBoundaryAt150() {
    let after = "7k/8/8/8/3n4/8/P7/2R3K1 b - - 0 1"
    let f = facts("7k/8/8/8/3n4/8/P7/2R3K1 w - - 0 1", after, uci: "a2a3", san: "a3", best: "c1c8",
                  reply: "d4e2", cpLoss: 150)
    #expect(detectMotifs(f).contains(.allowedFork))
}

@Test func openingPrincipleBoundaries() {
    let before = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"
    func f(_ loss: Int, _ n: Int) -> MoveFacts {
        facts(before, uci: "d1h5", san: "Qh5", best: "g1f3", cpLoss: loss, moveNumber: n)
    }
    #expect(detectMotifs(f(60, 5)).contains(.openingPrinciple))
    #expect(!detectMotifs(f(60, 6)).contains(.openingPrinciple))
    #expect(detectMotifs(f(50, 3)).contains(.openingPrinciple))
    #expect(!detectMotifs(f(49, 3)).contains(.openingPrinciple))
}

@Test func motifOrderIsSpecOrder() {
    let ng5 = facts(italianBefore, uci: "f3g5", san: "Ng5", best: "f3e5", cpLoss: 320, mateAgainst: 2, moveNumber: 3)
    #expect(detectMotifs(ng5) == [.allowedMate, .hangingPiece, .missedCapture])

    let before = "7k/B7/8/8/3n4/8/1P6/2R3K1 w - - 0 1"
    let f = facts(before, uci: "b2b3", san: "b3", best: "a7d4", reply: "d4e2", cpLoss: 300)
    #expect(detectMotifs(f) == [.hangingPiece, .allowedFork, .missedCapture])
}
