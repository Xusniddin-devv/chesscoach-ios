import Foundation

public func pieceValue(_ kind: Piece.Kind) -> Int {
    switch kind {
    case .pawn: 1
    case .knight, .bishop: 3
    case .rook: 5
    case .queen: 9
    case .king: 100
    }
}

/// Whether the piece the mover just placed on its target square can be captured for less
/// than it is worth (or cannot be defended at all).
public func isEnPrise(fenAfter: String, uci: String, mover: Piece.Color) -> Bool {
    guard let to = targetSquare(uci), let position = Position(fen: fenAfter),
          let piece = position.piece(at: to), piece.color == mover else { return false }

    let attackers = Rules.attackers(of: to, by: mover.opposite, in: position)
    guard let cheapestAttacker = attackers.compactMap({ position.piece(at: $0)?.kind }).map(pieceValue).min() else {
        return false
    }
    let defenders = Rules.attackers(of: to, by: mover, in: position)
    return defenders.isEmpty || cheapestAttacker < pieceValue(piece.kind)
}

/// Material value captured by `uci` in `fenBefore` (en passant counts as a pawn).
public func capturedValue(fenBefore: String, uci: String) -> Int {
    guard let (from, to) = uciSquares(uci), let position = Position(fen: fenBefore) else { return 0 }
    if let target = position.piece(at: to) {
        return pieceValue(target.kind)
    }
    if let mover = position.piece(at: from), mover.kind == .pawn, from.file.number != to.file.number {
        return 1
    }
    return 0
}

/// A move is a sacrifice when the moved piece is en prise and worth more than what it captured.
public func isSacrifice(fenBefore: String, fenAfter: String, uci: String, mover: Piece.Color) -> Bool {
    guard let to = targetSquare(uci), let position = Position(fen: fenAfter),
          let piece = position.piece(at: to) else { return false }
    return isEnPrise(fenAfter: fenAfter, uci: uci, mover: mover)
        && pieceValue(piece.kind) > capturedValue(fenBefore: fenBefore, uci: uci)
}

private func uciSquares(_ uci: String) -> (Square, Square)? {
    let chars = Array(uci)
    guard chars.count == 4 || chars.count == 5 else { return nil }
    let from = String(chars[0...1]), to = String(chars[2...3])
    guard isSquareNotation(from), isSquareNotation(to) else { return nil }
    return (Square(from), Square(to))
}

private func targetSquare(_ uci: String) -> Square? {
    uciSquares(uci)?.1
}

private func isSquareNotation(_ s: String) -> Bool {
    let c = Array(s)
    return c.count == 2 && ("a"..."h").contains(c[0]) && ("1"..."8").contains(c[1])
}
