import ChessCore

/// The user's accuracy for a game, from their own verdicts only (bot moves are not graded).
///
/// Each verdict gives the position after the user's move (`evalWhiteCp`) and, through
/// `winDrop`, the position before it. The positions run before₁, after₁, before₂, after₂, …;
/// the step from afterₖ to beforeₖ₊₁ is the bot's reply, so the user is scored only on their
/// own steps. Returns nil when the user has no graded move.
func userAccuracy(verdicts: [Verdict], userColor: Piece.Color) -> Double? {
    let own = verdicts.filter { $0.mover == userColor }.sorted { $0.ply < $1.ply }
    guard !own.isEmpty else { return nil }

    func white(_ moverWin: Double) -> Double { userColor == .white ? moverWin : 100 - moverWin }

    var whiteWin: [Double] = []
    var movers: [Piece.Color] = []
    for (i, v) in own.enumerated() {
        let afterWhite = winPercent(Double(v.evalWhiteCp))
        let moverAfter = userColor == .white ? afterWhite : 100 - afterWhite
        if i > 0 { movers.append(userColor.opposite) }
        whiteWin += [white(moverAfter + v.winDrop), afterWhite]
        movers.append(userColor)
    }
    let result = gameAccuracy(whiteWin: whiteWin, movers: movers)
    return userColor == .white ? result.white : result.black
}
