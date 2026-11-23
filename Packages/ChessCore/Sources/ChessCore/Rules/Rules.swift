import Foundation
@_exported import ChessKit

public struct AppliedMove: Sendable, Equatable {
    public var fenAfter: String
    public var san: String
    public var isCapture: Bool
    public var isEnPassant: Bool
    public var isCastle: Bool
    public var promotion: Piece.Kind?
}

public enum GameState: Equatable, Sendable {
    case active
    case check
    case checkmate(winner: Piece.Color)
    case stalemate
    case insufficientMaterial
    case threefold
    case fiftyMove
}

public enum Rules {
    public static let startFen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    // MARK: Attackers

    private static let knightOffsets = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
    private static let kingOffsets = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
    private static let diagonals = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    private static let orthogonals = [(1, 0), (-1, 0), (0, 1), (0, -1)]

    private static func square(file: Int, rank: Int) -> Square? {
        guard (1...8).contains(file), (1...8).contains(rank) else { return nil }
        return Square("\(Square.File(file).rawValue)\(rank)")
    }

    /// Squares of `color` pieces that attack `square` (pseudo-attacks: pins are ignored).
    public static func attackers(of square: Square, by color: Piece.Color, in position: Position) -> [Square] {
        let f = square.file.number
        let r = square.rank.value
        var result: [Square] = []

        func look(_ kind: Piece.Kind, _ offsets: [(Int, Int)]) {
            for (df, dr) in offsets {
                if let s = Self.square(file: f + df, rank: r + dr),
                   let p = position.piece(at: s), p.color == color, p.kind == kind {
                    result.append(s)
                }
            }
        }
        func slide(_ dirs: [(Int, Int)], _ kinds: Set<Piece.Kind>) {
            for (df, dr) in dirs {
                var cf = f + df, cr = r + dr
                while let s = Self.square(file: cf, rank: cr) {
                    if let p = position.piece(at: s) {
                        if p.color == color, kinds.contains(p.kind) { result.append(s) }
                        break
                    }
                    cf += df; cr += dr
                }
            }
        }

        // A white pawn attacks upward, so it sits one rank below the target.
        let pawnRankDelta = color == .white ? -1 : 1
        look(.pawn, [(-1, pawnRankDelta), (1, pawnRankDelta)])
        look(.knight, knightOffsets)
        look(.king, kingOffsets)
        slide(diagonals, [.bishop, .queen])
        slide(orthogonals, [.rook, .queen])
        return result
    }

    // MARK: Position helpers

    public static func piece(at square: Square, fen: String) -> Piece? {
        Position(fen: fen)?.piece(at: square)
    }

    public static func legalMoveCount(fen: String) -> Int? {
        guard let position = Position(fen: fen) else { return nil }
        return legalMoveCount(position: position)
    }

    private static func legalMoveCount(position: Position) -> Int {
        let board = Board(position: position)
        var count = 0
        for piece in position.pieces where piece.color == position.sideToMove {
            let targets = board.legalMoves(forPieceAt: piece.square)
            if piece.kind == .pawn {
                let lastRank = piece.color == .white ? 8 : 1
                for t in targets { count += t.rank.value == lastRank ? 4 : 1 }
            } else {
                count += targets.count
            }
        }
        return count
    }

    // MARK: Applying moves

    public static func apply(uci: String, to fen: String) -> AppliedMove? {
        guard let position = Position(fen: fen) else { return nil }
        return apply(uci: uci, to: position)
    }

    private static func apply(uci: String, to position: Position) -> AppliedMove? {
        let chars = Array(uci)
        guard chars.count == 4 || chars.count == 5 else { return nil }
        let from = String(chars[0...1]), to = String(chars[2...3])
        guard isSquare(from), isSquare(to) else { return nil }
        let start = Square(from), end = Square(to)

        var promotion: Piece.Kind?
        if chars.count == 5 {
            switch chars[4] {
            case "q": promotion = .queen
            case "r": promotion = .rook
            case "b": promotion = .bishop
            case "n": promotion = .knight
            default: return nil
            }
        }

        guard let mover = position.piece(at: start), mover.color == position.sideToMove else { return nil }
        let targetWasEmpty = position.piece(at: end) == nil

        var board = Board(position: position)
        guard var move = board.move(pieceAt: start, to: end) else { return nil }

        if case .promotion = board.state {
            // Promotion without a suffix is not a valid UCI move.
            guard let kind = promotion else { return nil }
            move = board.completePromotion(of: move, to: kind)
        } else if promotion != nil {
            return nil
        }

        var isCapture = false
        var isCastle = false
        switch move.result {
        case .capture: isCapture = true
        case .castle: isCastle = true
        case .move: break
        }
        let isEnPassant = isCapture && mover.kind == .pawn && targetWasEmpty

        return AppliedMove(
            fenAfter: board.position.fen,
            san: move.san,
            isCapture: isCapture,
            isEnPassant: isEnPassant,
            isCastle: isCastle,
            promotion: promotion
        )
    }

    private static func isSquare(_ s: String) -> Bool {
        let c = Array(s)
        return c.count == 2 && ("a"..."h").contains(c[0]) && ("1"..."8").contains(c[1])
    }

    public static func fen(startFen: String, moves: [String]) -> String? {
        var fen = startFen
        for m in moves {
            guard let applied = apply(uci: m, to: fen) else { return nil }
            fen = applied.fenAfter
        }
        return fen
    }

    // MARK: Game state

    public static func state(fen: String, history: [String]) -> GameState {
        guard let position = Position(fen: fen) else { return .active }

        let king = position.pieces.first { $0.kind == .king && $0.color == position.sideToMove }
        let inCheck = king.map {
            !attackers(of: $0.square, by: position.sideToMove.opposite, in: position).isEmpty
        } ?? false

        if legalMoveCount(position: position) == 0 {
            return inCheck ? .checkmate(winner: position.sideToMove.opposite) : .stalemate
        }
        if position.hasInsufficientMaterial { return .insufficientMaterial }
        if isThreefold(fen: fen, history: history) { return .threefold }
        if position.clock.halfmoves >= 100 { return .fiftyMove }
        return inCheck ? .check : .active
    }

    private static func repetitionKey(_ fen: String) -> String {
        fen.split(separator: " ").prefix(4).joined(separator: " ")
    }

    private static func isThreefold(fen: String, history: [String]) -> Bool {
        let target = repetitionKey(fen)
        var current = startFen
        var count = repetitionKey(current) == target ? 1 : 0
        for m in history {
            guard let applied = apply(uci: m, to: current) else { return false }
            current = applied.fenAfter
            if repetitionKey(current) == target { count += 1 }
        }
        return count >= 3
    }
}
