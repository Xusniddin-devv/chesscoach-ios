import ChessCore

/// Tap-to-move and drag-drop state for the board, kept free of SwiftUI so it can be tested.
/// `side` is the colour allowed to move; nothing is selectable when it is not that side's turn.
struct BoardInteraction: Equatable {
    enum TapResult: Equatable {
        case selected(Square, targets: [Square])
        case move(String)
        case needsPromotion(from: Square, to: Square)
        case cleared
    }

    private(set) var selected: Square?
    private(set) var targets: [Square] = []

    mutating func tap(_ square: Square, fen: String, side: Piece.Color) -> TapResult {
        guard let position = Position(fen: fen), position.sideToMove == side else { return clear() }

        if let from = selected {
            if square == from { return clear() }
            if targets.contains(square) { return play(from: from, to: square, position: position) }
        }
        if let piece = position.piece(at: square), piece.color == side {
            selected = square
            targets = Board(position: position).legalMoves(forPieceAt: square).sorted { $0.rawValue < $1.rawValue }
            return .selected(square, targets: targets)
        }
        return clear()
    }

    /// A drag released over `to`. Illegal drops leave the dragged piece selected.
    mutating func drop(from: Square, to: Square, fen: String, side: Piece.Color) -> TapResult {
        if selected != from {
            guard case .selected = tap(from, fen: fen, side: side) else { return clear() }
        }
        guard to != from, targets.contains(to), let position = Position(fen: fen) else {
            return .selected(from, targets: targets)
        }
        return play(from: from, to: to, position: position)
    }

    @discardableResult
    mutating func clear() -> TapResult {
        selected = nil
        targets = []
        return .cleared
    }

    private mutating func play(from: Square, to: Square, position: Position) -> TapResult {
        let piece = position.piece(at: from)
        clear()
        let lastRank = piece?.color == .white ? 8 : 1
        if piece?.kind == .pawn, to.rank.value == lastRank {
            return .needsPromotion(from: from, to: to)
        }
        return .move(from.notation + to.notation)
    }
}
