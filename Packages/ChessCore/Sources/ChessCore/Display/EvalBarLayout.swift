import Foundation

/// Eval bar geometry rules. The light segment always represents White.
public struct EvalBarLayout {
    /// Fraction of the bar filled by White (win percentage / 100).
    public static func whiteFraction(whiteCp: Double) -> Double {
        winPercent(whiteCp) / 100
    }

    /// White's segment sits at the bottom when White is at the bottom of the board.
    public static func whiteAnchoredAtBottom(orientation: Piece.Color) -> Bool {
        orientation == .white
    }
}
