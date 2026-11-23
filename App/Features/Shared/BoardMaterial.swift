import ChessCore

/// What each side has captured in a position, for the player bars (Play and Review).
enum BoardMaterial {
    private static let startCounts: [Piece.Kind: Int] = [.pawn: 8, .knight: 2, .bishop: 2, .rook: 2, .queen: 1]
    private static let trayOrder: [Piece.Kind] = [.pawn, .knight, .bishop, .rook, .queen]

    /// Pieces `color` has taken, cheapest first (promotions can hide a capture; good enough for a tray).
    static func captured(by color: Piece.Color, fen: String) -> [Piece] {
        let pieces = Position(fen: fen)?.pieces ?? []
        return trayOrder.flatMap { kind -> [Piece] in
            let left = pieces.filter { $0.color == color.opposite && $0.kind == kind }.count
            let missing = max(0, (startCounts[kind] ?? 0) - left)
            return Array(repeating: Piece(kind, color: color.opposite, square: .a1), count: missing)
        }
    }

    /// Material `color` is ahead by, in pawns (0 when level or behind).
    static func lead(for color: Piece.Color, fen: String) -> Int {
        let pieces = (Position(fen: fen)?.pieces ?? []).filter { $0.kind != .king }
        let own = pieces.filter { $0.color == color }.map { pieceValue($0.kind) }.reduce(0, +)
        let other = pieces.filter { $0.color != color }.map { pieceValue($0.kind) }.reduce(0, +)
        return max(0, own - other)
    }

    /// "bp", "wn": the piece's asset name without the folder.
    static func code(_ piece: Piece) -> String {
        String(PieceImage.assetName(piece).dropFirst("Pieces/".count))
    }

    /// A player bar's tray for `color` in `fen`.
    static func tray(for color: Piece.Color, fen: String) -> (captured: [String], lead: Int) {
        (captured(by: color, fen: fen).map(code), lead(for: color, fen: fen))
    }
}
