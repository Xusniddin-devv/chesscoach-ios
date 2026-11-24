import Foundation

/// One finished game as the rating estimate sees it.
public struct RatedGame: Sendable, Equatable {
    /// The result from the user's side.
    public enum Outcome: Sendable, Equatable { case win, draw, loss }

    public var botElo: Int
    public var outcome: Outcome
    /// The user's accuracy in the game, when known.
    public var accuracy: Double?

    public init(botElo: Int, outcome: Outcome, accuracy: Double?) {
        self.botElo = botElo
        self.outcome = outcome
        self.accuracy = accuracy
    }
}

/// The player's estimated rating (web `rating.ts`). `games` are newest first; the newest 15
/// count. Each game is worth its performance `elo + 400·(score − 0.5)·0.9`, blended 70 / 30 with
/// an accuracy rating `500 + (accuracy − 60) / 35 · 1400` (clamped to 300…2400) when the
/// accuracy is known. The average is clamped to 300…2400 and rounded to 10.
/// Nil with fewer than 3 games.
public func estimateRating(_ games: [RatedGame]) -> Int? {
    let recent = games.prefix(15)
    guard recent.count >= 3 else { return nil }
    let values = recent.map { game -> Double in
        let score: Double = switch game.outcome {
        case .win: 1
        case .draw: 0.5
        case .loss: 0
        }
        let performance = Double(game.botElo) + 400 * (score - 0.5) * 0.9
        guard let accuracy = game.accuracy else { return performance }
        let accuracyRating = min(max(500 + (accuracy - 60) / 35 * 1400, 300), 2400)
        return 0.7 * performance + 0.3 * accuracyRating
    }
    let average = min(max(values.reduce(0, +) / Double(values.count), 300), 2400)
    return Int(((average / 10) + 0.5).rounded(.down)) * 10  // JS Math.round
}

/// Rating milestones (web levels, web-rules.md "Engine strength").
public let ratingMilestones: [(elo: Int, name: String)] = [
    (600, "Beginner I"), (800, "Beginner II"), (1000, "Novice I"), (1200, "Novice II"),
    (1320, "Club I"), (1500, "Club II"), (1700, "Strong I"), (1900, "Strong II"),
    (2100, "Advanced"), (2300, "Expert"),
]

/// The first milestone above `estimate`; nil from the top one up.
public func nextMilestone(_ estimate: Int) -> (elo: Int, name: String)? {
    ratingMilestones.first { $0.elo > estimate }
}

/// The highest milestone reached; nil below the first.
public func currentMilestone(_ estimate: Int) -> (elo: Int, name: String)? {
    ratingMilestones.last { $0.elo <= estimate }
}

/// The player's level as a chess piece: Pawn below 800, Knight 800-1199, Bishop 1200-1499,
/// Rook 1500-1799, Queen 1800-2099, King from 2100.
public enum RatingTier: Int, CaseIterable, Sendable, Comparable {
    case pawn, knight, bishop, rook, queen, king

    public init(rating: Int) {
        self = Self.allCases.last { $0.lowerBound <= rating } ?? .pawn
    }

    /// The lowest rating of the tier (the Pawn starts at the estimate's floor, 300).
    public var lowerBound: Int {
        switch self {
        case .pawn: 300
        case .knight: 800
        case .bishop: 1200
        case .rook: 1500
        case .queen: 1800
        case .king: 2100
        }
    }

    public var next: RatingTier? { RatingTier(rawValue: rawValue + 1) }

    public var name: String {
        switch self {
        case .pawn: "Pawn"
        case .knight: "Knight"
        case .bishop: "Bishop"
        case .rook: "Rook"
        case .queen: "Queen"
        case .king: "King"
        }
    }

    public var pieceKind: Piece.Kind {
        switch self {
        case .pawn: .pawn
        case .knight: .knight
        case .bishop: .bishop
        case .rook: .rook
        case .queen: .queen
        case .king: .king
        }
    }

    /// Points still needed for the next tier; nil for the King.
    public func pointsToNext(from rating: Int) -> Int? {
        next.map { max(0, $0.lowerBound - rating) }
    }

    /// Points from `rating` to the next tier above the one it is in; nil at King.
    public static func pointsToNext(from rating: Int) -> Int? {
        RatingTier(rating: rating).pointsToNext(from: rating)
    }

    /// How far `rating` is through this tier towards the next, 0…1 (1 for the King).
    public func progress(of rating: Int) -> Double {
        guard let next else { return 1 }
        let span = Double(next.lowerBound - lowerBound)
        return min(max(Double(rating - lowerBound) / span, 0), 1)
    }

    public static func < (lhs: RatingTier, rhs: RatingTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// How often one kind of mistake happened, and when last.
public struct WeaknessSummary: Sendable, Equatable {
    public var motif: Motif
    public var count: Int
    public var lastSeen: Date

    public init(motif: Motif, count: Int, lastSeen: Date) {
        self.motif = motif
        self.count = count
        self.lastSeen = lastSeen
    }
}

/// Counts every motif of the user's negative moves (one item per move), most frequent first;
/// ties go to the most recently seen.
public func aggregateWeaknesses(_ items: [(motifs: [Motif], date: Date)]) -> [WeaknessSummary] {
    var byMotif: [Motif: WeaknessSummary] = [:]
    for item in items {
        for motif in item.motifs {
            if var summary = byMotif[motif] {
                summary.count += 1
                summary.lastSeen = max(summary.lastSeen, item.date)
                byMotif[motif] = summary
            } else {
                byMotif[motif] = WeaknessSummary(motif: motif, count: 1, lastSeen: item.date)
            }
        }
    }
    return byMotif.values.sorted {
        if $0.count != $1.count { return $0.count > $1.count }
        if $0.lastSeen != $1.lastSeen { return $0.lastSeen > $1.lastSeen }
        return $0.motif.rawValue < $1.motif.rawValue
    }
}

public extension Motif {
    /// A beginner's name for the habit.
    var title: String {
        switch self {
        case .hangingPiece: "Leaving pieces undefended"
        case .missedMate: "Missing checkmates"
        case .allowedMate: "Allowing checkmate"
        case .allowedFork: "Walking into forks"
        case .missedCapture: "Missing free captures"
        case .openingPrinciple: "Queen out too early"
        }
    }

    /// The habit said to the player: "You leave pieces undefended".
    var headline: String {
        switch self {
        case .hangingPiece: "You leave pieces undefended"
        case .missedMate: "You miss checkmates"
        case .allowedMate: "You allow checkmates"
        case .allowedFork: "You walk into forks"
        case .missedCapture: "You miss free captures"
        case .openingPrinciple: "You bring the queen out early"
        }
    }

    /// One sentence on what to do about it.
    var advice: String {
        switch self {
        case .hangingPiece: "Before you let go of a piece, check that it is protected on its new square."
        case .missedMate: "When the enemy king is short of squares, look at every check first."
        case .allowedMate: "Before each move, ask which checks your opponent will have next."
        case .allowedFork: "Watch for knight and queen moves that could attack two of your pieces at once."
        case .missedCapture: "Each turn, look at what you can take before anything else."
        case .openingPrinciple: "In the first moves, develop knights and bishops before the queen."
        }
    }
}
