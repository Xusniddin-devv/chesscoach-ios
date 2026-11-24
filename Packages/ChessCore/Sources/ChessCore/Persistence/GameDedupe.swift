import Foundation

/// Copies of one game (same stable id) can meet after a CloudKit sync: a re-import on a
/// second phone, or two devices saving the same game before they sync.
///
/// Two separate choices:
/// - **Which content to show** (`keeper`): the best copy by content. Used on read and to
///   fill the surviving row.
/// - **Which row survives a merge** (`survivor`): never by content or fetch order, which
///   differ between devices mid-sync - two devices could each keep their own row, delete
///   the other's, and lose the game everywhere. The smallest immutable row id is the same
///   choice on every device.
public enum GameDedupe {
    /// The index of the copy to show: a full analysis first, then any analysis, then the
    /// longer game (an analysis-board line that grew on one device). Ties keep the earliest
    /// index, so callers pass the copies in their own preference order (newest first).
    public static func keeper(_ copies: [GameSnapshot]) -> Int? {
        guard var best = copies.indices.first else { return nil }
        for i in copies.indices.dropFirst() where rank(copies[i]) > rank(copies[best]) { best = i }
        return best
    }

    /// The index of the row that survives a merge: the smallest row id. Nil when that id is
    /// shared (rows that can't be told apart the same way everywhere are all kept).
    public static func survivor(rowIDs: [UUID]) -> Int? {
        guard let smallest = rowIDs.min(by: { $0.uuidString < $1.uuidString }),
              rowIDs.filter({ $0 == smallest }).count == 1 else { return nil }
        return rowIDs.firstIndex(of: smallest)
    }

    private static func rank(_ game: GameSnapshot) -> (analysis: Int, moves: Int) {
        (game.analysis.map { $0.isFull ? 2 : 1 } ?? 0, game.moves.count)
    }
}
