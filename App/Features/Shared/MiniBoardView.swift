import SwiftUI
import ChessCore

/// A small, static board: the position of `fen` with the real piece art, an optional
/// highlighted square (class tint at 55 %) and a move-class badge on its corner. No
/// coordinates, no interaction. Profile's game filmstrip and weakness card use it.
struct MiniBoardView: View {
    let fen: String
    var highlight: Square?
    var badge: MoveClass?
    var orientation: Piece.Color = .white

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let pieces = Position(fen: fen)?.pieces ?? []
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let cell = size.width / 8
                    for row in 0..<8 {
                        for column in 0..<8 {
                            let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                            let light = (row + column).isMultiple(of: 2)
                            context.fill(Path(rect), with: .color(light ? DS.Color.boardLight : DS.Color.boardDark))
                        }
                    }
                    if let highlight {
                        let rect = BoardGeometry.rect(for: highlight, orientation: orientation, side: size.width)
                        context.fill(Path(rect), with: .color(DS.Color.moveClass(badge ?? .blunder).opacity(0.55)))
                    }
                }
                ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                    let rect = BoardGeometry.rect(for: piece.square, orientation: orientation, side: side)
                    PieceImage(piece: piece)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.small))
            .overlay(alignment: .topLeading) {
                if let highlight, let badge {
                    let rect = BoardGeometry.rect(for: highlight, orientation: orientation, side: side)
                    MoveBadge(moveClass: badge)
                        .scaleEffect(0.82)
                        .position(x: rect.maxX - 1, y: rect.minY + 1)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
