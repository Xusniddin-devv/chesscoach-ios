import Foundation

/// White-relative centipawns for a UCI score. `sideToMove` is the side to move in the
/// position the score was reported for. Mates map to ±(10000 − 10·N). `mate 0` means the side
/// to move is already checkmated, so it maps to −10000 from that side's view (deliberate
/// deviation from the web app, which mapped it to 0; see web-rules.md "Score").
public func toCp(_ score: Score, sideToMove: Piece.Color) -> Double {
    let v: Double
    if let mate = score.mate {
        v = mate == 0 ? -10000 : (mate > 0 ? 1 : -1) * Double(10000 - 10 * abs(mate))
    } else {
        v = Double(score.cp ?? 0)
    }
    return sideToMove == .white ? v : -v
}

/// White win percentage for a White-relative centipawn value. Clamped to ±1500 cp.
public func winPercent(_ whiteCp: Double) -> Double {
    let clamped = min(max(whiteCp, -1500), 1500)
    return 50 + 50 * (2 / (1 + exp(-0.00368208 * clamped)) - 1)
}
