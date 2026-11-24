import Foundation

/// The player's puzzle rating: Elo against the puzzle's rating, from the first outcome of
/// each puzzle only (a retry or a hint never earns points back).
public enum PuzzleRating {
    public static let k: Double = 24

    /// Points won (positive) or lost (negative) for one outcome.
    public static func delta(player: Int, puzzle: Int, solved: Bool) -> Int {
        let expected = 1 / (1 + pow(10, Double(puzzle - player) / 400))
        let change = k * ((solved ? 1 : 0) - expected)
        return Int(change.rounded())
    }

    public static func updated(_ player: Int, puzzle: Int, solved: Bool) -> Int {
        min(max(player + delta(player: player, puzzle: puzzle, solved: solved), 100), 3000)
    }
}
