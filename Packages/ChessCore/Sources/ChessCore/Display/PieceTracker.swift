public struct TrackedPiece: Identifiable, Sendable, Equatable {
    public let id: Int
    public var piece: Piece
    public var square: Square
}

/// Tracks pieces with stable ids across moves so views can animate them.
public struct PieceTracker: Sendable, Equatable {
    public private(set) var pieces: [TrackedPiece]

    public init(fen: String) {
        let found = Position(fen: fen)?.pieces ?? []
        pieces = found.enumerated().map { TrackedPiece(id: $0.offset, piece: $0.element, square: $0.element.square) }
    }

    /// Applies `uci`, played from `fenBefore`. An illegal move leaves the tracker unchanged.
    public mutating func apply(_ uci: String, fenBefore: String) {
        guard let applied = Rules.apply(uci: uci, to: fenBefore) else { return }
        let from = Square(String(uci.prefix(2))), to = Square(String(uci.dropFirst(2).prefix(2)))
        guard pieces.contains(where: { $0.square == from }) else { return }

        if applied.isEnPassant {
            // The captured pawn sits beside the destination, on the mover's starting rank.
            let victim = Square(String(to.file.rawValue) + String(from.rank.value))
            pieces.removeAll { $0.square == victim }
        } else if applied.isCapture {
            pieces.removeAll { $0.square == to }
        }
        guard let i = pieces.firstIndex(where: { $0.square == from }) else { return }

        if applied.isCastle {
            let kingside = to.file.number > from.file.number
            let rookFrom = Square((kingside ? "h" : "a") + String(from.rank.value))
            let rookTo = Square((kingside ? "f" : "d") + String(from.rank.value))
            if let r = pieces.firstIndex(where: { $0.square == rookFrom }) {
                pieces[r].square = rookTo
                pieces[r].piece.square = rookTo
            }
        }
        pieces[i].square = to
        pieces[i].piece.square = to
        if let kind = applied.promotion { pieces[i].piece.kind = kind }
    }
}
