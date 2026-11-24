import Foundation

/// Something that makes an edited position impossible to analyse.
public enum PositionProblem: Equatable, Hashable, Sendable {
    /// `count` kings of `color` (one is needed).
    case kingCount(Piece.Color, count: Int)
    /// The side that is not to move is in check: it would be captured next move.
    case sideNotToMoveInCheck(Piece.Color)
    /// A pawn on the first or last rank.
    case pawnOnBackRank
    /// More than 16 pieces of `color`.
    case tooManyPieces(Piece.Color)
    /// More than 8 pawns of `color`.
    case tooManyPawns(Piece.Color)

    /// One friendly sentence for the editor's inline message.
    public var message: String {
        switch self {
        case .kingCount(let color, 0):
            "Add a \(Self.name(color)) king."
        case .kingCount(let color, _):
            "Only one \(Self.name(color)) king, please."
        case .sideNotToMoveInCheck(let color):
            "\(Self.name(color).capitalized)'s king is in check, so it has to be \(Self.name(color).capitalized) to move."
        case .pawnOnBackRank:
            "Pawns can't stand on the first or last rank."
        case .tooManyPieces(let color):
            "\(Self.name(color).capitalized) has more than 16 pieces."
        case .tooManyPawns(let color):
            "\(Self.name(color).capitalized) has more than 8 pawns."
        }
    }

    private static func name(_ color: Piece.Color) -> String { color == .white ? "white" : "black" }
}

/// Checks an edited position before it is analysed: one king each, the side not to move not
/// in check, no pawns on the back ranks, at most 16 pieces (8 pawns) a side.
public enum PositionValidator {
    /// Every problem, most important first (kings, then check, then the rest). Empty: valid.
    public static func problems(_ setup: BoardSetup) -> [PositionProblem] {
        var problems: [PositionProblem] = []
        for color in [Piece.Color.white, .black] {
            let kings = setup.count(SetupPiece(color, .king))
            if kings != 1 { problems.append(.kingCount(color, count: kings)) }
        }
        if problems.isEmpty, let checked = sideNotToMoveInCheck(setup) {
            problems.append(.sideNotToMoveInCheck(checked))
        }
        if setup.pieces.contains(where: { $0.value.kind == .pawn && ($0.key.rank.value == 1 || $0.key.rank.value == 8) }) {
            problems.append(.pawnOnBackRank)
        }
        for color in [Piece.Color.white, .black] {
            if setup.count(color) > 16 { problems.append(.tooManyPieces(color)) }
            if setup.count(SetupPiece(color, .pawn)) > 8 { problems.append(.tooManyPawns(color)) }
        }
        return problems
    }

    public static func isValid(_ setup: BoardSetup) -> Bool { problems(setup).isEmpty }

    /// The side not to move, when its king is attacked.
    private static func sideNotToMoveInCheck(_ setup: BoardSetup) -> Piece.Color? {
        let waiting = setup.sideToMove.opposite
        guard let king = setup.pieces.first(where: { $0.value == SetupPiece(waiting, .king) })?.key,
              let position = Position(fen: setup.fen) else { return nil }
        return Rules.attackers(of: king, by: setup.sideToMove, in: position).isEmpty ? nil : waiting
    }
}
