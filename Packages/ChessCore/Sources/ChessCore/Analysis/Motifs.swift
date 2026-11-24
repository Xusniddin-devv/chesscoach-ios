public enum Motif: String, Codable, Sendable, Equatable {
    case allowedMate = "allowed-mate"
    case missedMate = "missed-mate"
    case hangingPiece = "hanging-piece"
    case allowedFork = "allowed-fork"
    case missedCapture = "missed-capture"
    case openingPrinciple = "opening-principle"
}

/// Why a move was bad, in the web app's fixed order. Call only for negative classes.
public func detectMotifs(_ f: MoveFacts) -> [Motif] {
    var motifs: [Motif] = []
    if f.mateAgainstMoverAfter != nil { motifs.append(.allowedMate) }
    if f.mateForMoverBefore != nil && f.mateAgainstMoverAfter == nil && f.cpLoss > 200 {
        motifs.append(.missedMate)
    }
    if isEnPrise(fenAfter: f.fenAfter, uci: f.playedUci, mover: f.mover) { motifs.append(.hangingPiece) }
    if allowsFork(f) { motifs.append(.allowedFork) }
    if f.cpLoss >= 100, Rules.apply(uci: f.bestUci, to: f.fenBefore)?.isCapture == true {
        motifs.append(.missedCapture)
    }
    if f.moveNumber <= 5, f.cpLoss >= 50, movedQueen(f) { motifs.append(.openingPrinciple) }
    return motifs
}

private func allowsFork(_ f: MoveFacts) -> Bool {
    guard !f.bestReplyUci.isEmpty, f.cpLoss >= 150,
          let reply = Rules.apply(uci: f.bestReplyUci, to: f.fenAfter),
          let (_, to) = uciSquares(f.bestReplyUci),
          let position = Position(fen: reply.fenAfter) else { return false }
    let forked = position.pieces.filter { piece in
        piece.color == f.mover && pieceValue(piece.kind) >= 3
            && Rules.attackers(of: piece.square, by: f.mover.opposite, in: position).contains(to)
    }
    return forked.count >= 2
}

private func movedQueen(_ f: MoveFacts) -> Bool {
    guard let (from, _) = uciSquares(f.playedUci) else { return false }
    return Rules.piece(at: from, fen: f.fenBefore)?.kind == .queen
}
