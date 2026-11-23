import Foundation

/// A tactic in the Lichess puzzle format.
///
/// `fen` is the position before the setup move. When `hasSetupMove` is true (every Lichess
/// puzzle), `moves[0]` is the opponent's move that creates the puzzle and is played
/// automatically; after it the solver and the opponent alternate, the solver first. Blunder
/// puzzles may have no setup move: then the solver moves first from `fen`.
public struct Puzzle: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var fen: String
    public var moves: [String]
    public var rating: Int
    public var themes: [String]
    public var hasSetupMove: Bool

    public init(id: String, fen: String, moves: [String], rating: Int, themes: [String], hasSetupMove: Bool = true) {
        self.id = id
        self.fen = fen
        self.moves = moves
        self.rating = rating
        self.themes = themes
        self.hasSetupMove = hasSetupMove
    }

    /// Index in `moves` of the solver's first move.
    public var firstSolverIndex: Int { hasSetupMove ? 1 : 0 }

    /// The position the solver faces.
    public var solvingFen: String? {
        hasSetupMove ? Rules.fen(startFen: fen, moves: Array(moves.prefix(1))) : fen
    }

    /// The side the solver plays.
    public var solverColor: Piece.Color {
        let stm: Piece.Color = fen.split(separator: " ").dropFirst().first == "b" ? .black : .white
        return hasSetupMove ? stm.opposite : stm
    }

    /// Number of moves the solver has to find.
    public var solverMoveCount: Int { (moves.count - firstSolverIndex + 1) / 2 }
}

extension Puzzle {
    private enum CodingKeys: String, CodingKey { case id, fen, moves, rating, themes, hasSetupMove }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        fen = try c.decode(String.self, forKey: .fen)
        moves = try c.decode([String].self, forKey: .moves)
        rating = try c.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        themes = try c.decodeIfPresent([String].self, forKey: .themes) ?? []
        hasSetupMove = try c.decodeIfPresent(Bool.self, forKey: .hasSetupMove) ?? true
    }
}
