/// Copies of one game (same stable id) can meet after a CloudKit sync: a re-import on a
/// second phone, or two devices saving the same game before they sync. One copy is kept.
public enum GameDedupe {
    /// The index of the copy to keep: a full analysis first, then any analysis, then the
    /// longer game (an analysis-board line that grew on one device). Ties keep the earliest
    /// index, so callers pass the copies in their own preference order (newest first).
    public static func keeper(_ copies: [GameSnapshot]) -> Int? {
        guard var best = copies.indices.first else { return nil }
        for i in copies.indices.dropFirst() where rank(copies[i]) > rank(copies[best]) { best = i }
        return best
    }

    private static func rank(_ game: GameSnapshot) -> (analysis: Int, moves: Int) {
        (game.analysis.map { $0.isFull ? 2 : 1 } ?? 0, game.moves.count)
    }
}
