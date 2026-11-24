import Foundation

extension Rules {
    /// Every legal move in `fen` as UCI (promotions spelled out for all four pieces).
    public static func legalMoves(fen: String) -> [String] {
        guard let position = Position(fen: fen) else { return [] }
        let board = Board(position: position)
        var moves: [String] = []
        for piece in position.pieces where piece.color == position.sideToMove {
            let from = piece.square.notation
            for target in board.legalMoves(forPieceAt: piece.square) {
                let uci = from + target.notation
                let lastRank = piece.color == .white ? 8 : 1
                if piece.kind == .pawn, target.rank.value == lastRank {
                    moves += ["q", "r", "b", "n"].map { uci + $0 }
                } else {
                    moves.append(uci)
                }
            }
        }
        return moves.sorted()
    }

    /// The UCI of the legal move written `san` in `fen` ("+", "#", "!" and "?" ignored).
    public static func uci(san: String, fen: String) -> String? {
        let wanted = normalizeSan(san)
        return legalMoves(fen: fen).first { uci in
            apply(uci: uci, to: fen).map { normalizeSan($0.san) == wanted } ?? false
        }
    }

    /// True when the side to move is checkmated.
    public static func isCheckmate(fen: String) -> Bool {
        if case .checkmate = state(fen: fen, history: [], startFen: fen) { return true }
        return false
    }

    /// True when the side NOT to move is in check: such a position cannot arise in a game.
    public static func opponentInCheck(fen: String) -> Bool {
        guard let position = Position(fen: fen),
              let king = position.pieces.first(where: { $0.kind == .king && $0.color == position.sideToMove.opposite })
        else { return false }
        return !attackers(of: king.square, by: position.sideToMove, in: position).isEmpty
    }

    private static func normalizeSan(_ san: String) -> String {
        san.filter { !"+#!?".contains($0) }.replacingOccurrences(of: "0-0", with: "O-O")
    }
}
