import Foundation

/// Per-game, per-color accuracy (web-rules.md "Accuracy"). `whiteWin[i]` is White's win % at
/// position i; `movers[i]` made the move from position i to i+1, so
/// `whiteWin.count == movers.count + 1`. A color with no moves scores 100.
public func gameAccuracy(whiteWin: [Double], movers: [Piece.Color]) -> (white: Double, black: Double) {
    let window = Int(min(max(jsRound(Double(whiteWin.count) / 10), 2), 8))

    func accuracy(for color: Piece.Color) -> Double {
        var sumAccW = 0.0, sumW = 0.0, sumWOverAcc = 0.0
        for (i, mover) in movers.enumerated() where mover == color {
            let before = color == .white ? whiteWin[i] : 100 - whiteWin[i]
            let after = color == .white ? whiteWin[i + 1] : 100 - whiteWin[i + 1]
            let acc = min(max(103.1668 * exp(-0.04354 * max(0, before - after)) - 3.1669, 0), 100)
            let slice = whiteWin[max(0, i + 1 - window) ..< min(i + 2, whiteWin.count)]
            let weight = min(max(populationStdDev(slice), 0.5), 12)
            sumAccW += acc * weight
            sumW += weight
            sumWOverAcc += weight / max(acc, 1)
        }
        guard sumW > 0 else { return 100 }
        let arithmetic = sumAccW / sumW
        let harmonic = sumW / sumWOverAcc
        return jsRound(((arithmetic + harmonic) / 2) * 10) / 10
    }

    return (accuracy(for: .white), accuracy(for: .black))
}

/// JS `Math.round`: ties round toward +infinity.
private func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

private func populationStdDev(_ values: ArraySlice<Double>) -> Double {
    guard !values.isEmpty else { return 0 }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    return variance.squareRoot()
}
