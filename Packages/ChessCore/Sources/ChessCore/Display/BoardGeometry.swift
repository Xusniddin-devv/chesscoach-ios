import CoreGraphics

/// Maps squares to rects (and points back to squares) for a square board of `side` points.
/// Origin is top-left; White orientation puts a1 bottom-left, Black puts h8 bottom-left.
public enum BoardGeometry {
    public static func rect(for square: Square, orientation: Piece.Color, side: CGFloat) -> CGRect {
        let cell = side / 8
        let file = square.file.number - 1
        let rank = square.rank.value - 1
        let column = orientation == .white ? file : 7 - file
        let row = orientation == .white ? 7 - rank : rank
        return CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
    }

    public static func square(at point: CGPoint, orientation: Piece.Color, side: CGFloat) -> Square? {
        guard side > 0, point.x >= 0, point.y >= 0, point.x < side, point.y < side else { return nil }
        let cell = side / 8
        let column = min(Int(point.x / cell), 7)
        let row = min(Int(point.y / cell), 7)
        let file = orientation == .white ? column : 7 - column
        let rank = orientation == .white ? 7 - row : row
        let name = String(Square.File(file + 1).rawValue) + String(rank + 1)
        return Square(name)
    }
}
