import Foundation

public enum MoveWording: Sendable { case words, notation }

private func pieceName(_ kind: Piece.Kind) -> String {
    switch kind {
    case .pawn: "pawn"
    case .knight: "knight"
    case .bishop: "bishop"
    case .rook: "rook"
    case .queen: "queen"
    case .king: "king"
    }
}

private func motifText(_ m: Motif) -> String {
    switch m {
    case .hangingPiece: "your piece can simply be captured there"
    case .missedMate: "you had a forced checkmate available"
    case .allowedMate: "this allows a forced checkmate against you"
    case .allowedFork: "this lets the opponent fork two of your pieces"
    case .missedCapture: "you missed a capture that wins material"
    case .openingPrinciple: "this breaks an opening principle (develop minor pieces before the queen)"
    }
}

private func describe(uci: String, fen: String) -> String {
    guard let (from, to) = uciSquares(uci), let mover = Rules.piece(at: from, fen: fen) else { return uci }
    let f = from.notation, t = to.notation
    if let target = Rules.piece(at: to, fen: fen) {
        return "your \(pieceName(mover.kind)) on \(f) takes the \(pieceName(target.kind)) on \(t)"
    }
    return "your \(pieceName(mover.kind)) moves from \(f) to \(t)"
}

/// One-decimal, "." separated, locale independent (JS `toFixed(1)` for typical values).
private func pawns(_ cpLoss: Int) -> String {
    let tenths = Int((Double(cpLoss) / 10).rounded(.toNearestOrAwayFromZero))
    return "\(tenths / 10).\(abs(tenths % 10))"
}

public func explain(_ v: Verdict, wording: MoveWording) -> String {
    let words = wording == .words
    let bestUci = v.facts.bestUci
    let bestSan = Rules.apply(uci: bestUci, to: v.facts.fenBefore)?.san ?? bestUci
    let why = v.motifs.first.map(motifText)
        ?? "it gives up about \(pawns(v.cpLoss)) pawns of advantage"
        + (words ? " (chess engines measure positions in pawn-units: +1.0 means being one pawn ahead)" : "")
    let better = words ? "\(bestSan) - \(describe(uci: bestUci, fen: v.facts.fenBefore))" : bestSan
    return "\(v.san) is a \(v.classification.label.lowercased()): \(why). Better was \(better)."
}
