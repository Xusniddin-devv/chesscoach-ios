import Foundation

/// The coach's one line about a puzzle's solution, in `CoachText` markup: the key move in
/// bold, squares as `[e4]` chips. "**Nf5+** hits the king on [g7] and the queen on [d6]."
/// Built from the position (what the move attacks, check, mate) and the puzzle's themes.
public enum PuzzleExplainer {
    public static func line(for puzzle: Puzzle) -> String? {
        guard let fen = puzzle.solvingFen,
              puzzle.moves.indices.contains(puzzle.firstSolverIndex) else { return nil }
        let uci = puzzle.moves[puzzle.firstSolverIndex]
        guard let applied = Rules.apply(uci: uci, to: fen) else { return nil }
        let move = "**\(applied.san)**"
        let mover = puzzle.solverColor
        let themes = Set(puzzle.themes)
        let mateIn = [1, 2, 3, 4, 5].first { themes.contains("mateIn\($0)") }

        if Rules.isCheckmate(fen: applied.fenAfter) {
            return themes.contains("backRankMate") ? "\(move) mates on the back rank." : "\(move) is checkmate."
        }
        if let n = mateIn, n > 1 {
            return "\(move) starts a mate in \(n). Every reply loses."
        }
        let targets = attackedTargets(after: applied.fenAfter, from: Square(String(uci.dropFirst(2).prefix(2))), by: mover)
        if targets.count >= 2 {
            let named = targets.prefix(2).map { "the \($0.kind.word) on [\($0.square.notation)]" }
            return "\(move) hits \(named[0]) and \(named[1]) at once."
        }
        if applied.isCapture, let taken = Rules.piece(at: Square(String(uci.dropFirst(2).prefix(2))), fen: fen) {
            if themes.contains("hangingPiece") {
                return "\(move) takes the \(taken.kind.word) on [\(taken.square.notation)]. Nothing was guarding it."
            }
            if themes.contains("capturingDefender") {
                return "\(move) removes the defender. What it guarded falls next."
            }
            return "\(move) wins the \(taken.kind.word) on [\(taken.square.notation)]."
        }
        if themes.contains("pin") { return "\(move) pins a piece to something worth more behind it." }
        if themes.contains("skewer") { return "\(move) skewers: the piece in front moves, the one behind falls." }
        if themes.contains("discoveredAttack") { return "\(move) uncovers an attack from the piece behind it." }
        if let target = targets.first {
            return "\(move) goes after the \(target.kind.word) on [\(target.square.notation)]."
        }
        if applied.san.hasSuffix("+") { return "\(move) with check takes the initiative." }
        return "\(move) is the move. The point shows a move later."
    }

    /// Enemy pieces worth a knight or more (and the king) that the moved piece on `square`
    /// attacks after the move, the most valuable first.
    static func attackedTargets(after fen: String, from square: Square, by mover: Piece.Color) -> [Piece] {
        guard let position = Position(fen: fen) else { return [] }
        return position.pieces
            .filter { $0.color != mover && $0.kind != .pawn }
            .filter { Rules.attackers(of: $0.square, by: mover, in: position).contains(square) }
            .sorted { $0.kind.rank > $1.kind.rank }
    }
}

private extension Piece.Kind {
    var word: String {
        switch self {
        case .king: "king"
        case .queen: "queen"
        case .rook: "rook"
        case .bishop: "bishop"
        case .knight: "knight"
        case .pawn: "pawn"
        }
    }

    /// Ordering for "most valuable first".
    var rank: Int {
        switch self {
        case .king: 6
        case .queen: 5
        case .rook: 4
        case .bishop: 3
        case .knight: 2
        case .pawn: 1
        }
    }
}
