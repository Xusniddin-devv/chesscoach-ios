import Foundation

/// A piece without a square: what the position editor's tray holds and places.
public struct SetupPiece: Hashable, Sendable {
    public var color: Piece.Color
    public var kind: Piece.Kind

    public init(_ color: Piece.Color, _ kind: Piece.Kind) {
        self.color = color
        self.kind = kind
    }

    /// FEN letter: upper case for White.
    public var fenLetter: Character {
        let letter: Character = switch kind {
        case .pawn: "p"
        case .knight: "n"
        case .bishop: "b"
        case .rook: "r"
        case .queen: "q"
        case .king: "k"
        }
        return color == .white ? Character(letter.uppercased()) : letter
    }

    /// The tray's order: king first, pawn last.
    public static let trayKinds: [Piece.Kind] = [.king, .queen, .rook, .bishop, .knight, .pawn]
}

/// One castling right, as in FEN (`K`, `Q`, `k`, `q`).
public enum CastlingRight: String, CaseIterable, Hashable, Sendable {
    case whiteKingside = "K", whiteQueenside = "Q", blackKingside = "k", blackQueenside = "q"

    public var color: Piece.Color { self == .whiteKingside || self == .whiteQueenside ? .white : .black }

    /// The king and rook squares this right needs.
    public var kingSquare: Square { Square(color == .white ? "e1" : "e8") }
    public var rookSquare: Square {
        switch self {
        case .whiteKingside: Square("h1")
        case .whiteQueenside: Square("a1")
        case .blackKingside: Square("h8")
        case .blackQueenside: Square("a8")
        }
    }
}

/// The position editor's board: pieces on squares, side to move and castling rights, with
/// no move history (en passant is never set, clocks start at 0 / 1).
///
/// Castling rights the pieces can't support (king or rook off its home square) are kept as
/// the user's choice but left out of `fen`: moving the rook back turns the right on again.
public struct BoardSetup: Equatable, Sendable {
    public var pieces: [Square: SetupPiece]
    public var sideToMove: Piece.Color
    public var castling: Set<CastlingRight>

    public init(pieces: [Square: SetupPiece] = [:], sideToMove: Piece.Color = .white,
                castling: Set<CastlingRight> = []) {
        self.pieces = pieces
        self.sideToMove = sideToMove
        self.castling = castling
    }

    /// From a FEN's first three fields; nil when it does not parse.
    public init?(fen: String) {
        guard let position = Position(fen: fen) else { return nil }
        var pieces: [Square: SetupPiece] = [:]
        for piece in position.pieces { pieces[piece.square] = SetupPiece(piece.color, piece.kind) }
        let fields = fen.split(separator: " ")
        let rights = fields.count > 2 ? String(fields[2]) : "-"
        self.init(pieces: pieces, sideToMove: position.sideToMove,
                  castling: Set(rights.compactMap { CastlingRight(rawValue: String($0)) }))
    }

    public static let start = BoardSetup(fen: Rules.startFen)!
    public static let empty = BoardSetup()

    public subscript(square: Square) -> SetupPiece? {
        get { pieces[square] }
        set { pieces[square] = newValue }
    }

    /// Rights whose king and rook stand on their home squares.
    public var availableCastling: Set<CastlingRight> {
        Set(CastlingRight.allCases.filter { right in
            pieces[right.kingSquare] == SetupPiece(right.color, .king)
                && pieces[right.rookSquare] == SetupPiece(right.color, .rook)
        })
    }

    /// The rights that go into the FEN: chosen and possible.
    public var effectiveCastling: Set<CastlingRight> { castling.intersection(availableCastling) }

    public func count(_ color: Piece.Color) -> Int { pieces.values.filter { $0.color == color }.count }
    public func count(_ piece: SetupPiece) -> Int { pieces.values.filter { $0 == piece }.count }

    /// Full FEN: placement, side, castling, no en passant, clocks 0 1.
    public var fen: String {
        var ranks: [String] = []
        for rank in (1...8).reversed() {
            var row = ""
            var empty = 0
            for file in ["a", "b", "c", "d", "e", "f", "g", "h"] {
                if let piece = pieces[Square("\(file)\(rank)")] {
                    if empty > 0 { row += String(empty); empty = 0 }
                    row.append(piece.fenLetter)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { row += String(empty) }
            ranks.append(row)
        }
        let rights = CastlingRight.allCases.filter(effectiveCastling.contains).map(\.rawValue).joined()
        return "\(ranks.joined(separator: "/")) \(sideToMove == .white ? "w" : "b") \(rights.isEmpty ? "-" : rights) - 0 1"
    }
}
