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
    /// Own-mistake puzzles: only the key move is checked. The rest of `moves` (reply and
    /// continuation) is an engine line that is not verified unique, so it is demonstrated, never
    /// required. Bank puzzles keep their full lines (false).
    public var endsAfterKeyMove: Bool

    public init(id: String, fen: String, moves: [String], rating: Int, themes: [String],
                hasSetupMove: Bool = true, endsAfterKeyMove: Bool = false) {
        self.id = id
        self.fen = fen
        self.moves = moves
        self.rating = rating
        self.themes = themes
        self.hasSetupMove = hasSetupMove
        self.endsAfterKeyMove = endsAfterKeyMove
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

    /// Safe to serve: there is a solver move, and every move is legal in turn from `fen`, so
    /// the key move is legal in (and not already played on) the position the solver faces.
    /// A puzzle that fails this is dropped, never shown.
    public var isServable: Bool {
        guard moves.count > firstSolverIndex, let solving = solvingFen,
              Rules.apply(uci: moves[firstSolverIndex], to: solving) != nil else { return false }
        return Rules.fen(startFen: fen, moves: moves) != nil
    }

    /// Number of moves the solver has to find.
    public var solverMoveCount: Int { endsAfterKeyMove ? 1 : (moves.count - firstSolverIndex + 1) / 2 }
}

extension Puzzle {
    private enum CodingKeys: String, CodingKey { case id, fen, moves, rating, themes, hasSetupMove, endsAfterKeyMove }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        fen = try c.decode(String.self, forKey: .fen)
        moves = try c.decode([String].self, forKey: .moves)
        rating = try c.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        themes = try c.decodeIfPresent([String].self, forKey: .themes) ?? []
        hasSetupMove = try c.decodeIfPresent(Bool.self, forKey: .hasSetupMove) ?? true
        endsAfterKeyMove = try c.decodeIfPresent(Bool.self, forKey: .endsAfterKeyMove) ?? false
    }
}
