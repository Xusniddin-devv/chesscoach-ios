import Foundation

/// Rating tiers named after the pieces (profile concept): Pawn < 800, Knight 800–1199,
/// Bishop 1200–1499, Rook 1500–1799, Queen 1800–2099, King ≥ 2100.
public enum RatingTier: Int, CaseIterable, Sendable, Comparable {
    case pawn, knight, bishop, rook, queen, king

    public init(rating: Int) {
        self = Self.allCases.last { rating >= $0.floor } ?? .pawn
    }

    public static func < (a: RatingTier, b: RatingTier) -> Bool { a.rawValue < b.rawValue }

    /// Lowest rating of the tier.
    public var floor: Int {
        switch self {
        case .pawn: 0
        case .knight: 800
        case .bishop: 1200
        case .rook: 1500
        case .queen: 1800
        case .king: 2100
        }
    }

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

    /// The piece kind, for drawing it with the board's piece art.
    public var piece: Piece.Kind {
        switch self {
        case .pawn: .pawn
        case .knight: .knight
        case .bishop: .bishop
        case .rook: .rook
        case .queen: .queen
        case .king: .king
        }
    }

    public var next: RatingTier? { RatingTier(rawValue: rawValue + 1) }

    /// Points from `rating` to the next tier; nil at King.
    public static func pointsToNext(from rating: Int) -> Int? {
        RatingTier(rating: rating).next.map { $0.floor - rating }
    }
}
