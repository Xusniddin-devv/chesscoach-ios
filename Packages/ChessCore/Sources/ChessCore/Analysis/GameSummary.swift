import Foundation

/// The order the game-over panel lists move classes in: best news first.
public let moveClassSummaryOrder: [MoveClass] = [
    .brilliant, .great, .best, .excellent, .good, .book, .forced, .inaccuracy, .mistake, .miss, .blunder,
]

/// How many of `verdicts` fall in each class, only classes that occur, in `moveClassSummaryOrder`.
public func moveClassCounts(_ verdicts: [Verdict]) -> [(moveClass: MoveClass, count: Int)] {
    moveClassSummaryOrder.compactMap { moveClass in
        let count = verdicts.filter { $0.classification == moveClass }.count
        return count > 0 ? (moveClass, count) : nil
    }
}

/// The game's turning point: the move that threw away the most winning chances (largest
/// `winDrop`, either side; ties go to the earlier move). Nil when no move dropped at least
/// `threshold` win-percentage points (a clean game has no key moment).
public func keyMoment(_ verdicts: [Verdict], threshold: Double = 10) -> Verdict? {
    verdicts
        .filter { $0.winDrop >= threshold }
        .min { $0.winDrop != $1.winDrop ? $0.winDrop > $1.winDrop : $0.ply < $1.ply }
}
