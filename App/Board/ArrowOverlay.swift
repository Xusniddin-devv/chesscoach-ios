import SwiftUI
import ChessCore

/// Move arrows (centre to centre) drawn with `Canvas`: one solid shape per arrow with
/// softly rounded corners, 85 % of the given colour. No gradient, no glow. Never hit-tested.
struct ArrowOverlay: View {
    let arrows: [(Square, Square, Color)]
    let orientation: Piece.Color

    static let opacity = 0.85

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            for (from, to, color) in arrows where from != to {
                let path = Self.path(from: from, to: to, orientation: orientation, side: side)
                context.fill(path, with: .color(color.opacity(Self.opacity)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Outline of a straight arrow from the centre of `from` with its tip on the centre of `to`.
    static func path(from: Square, to: Square, orientation: Piece.Color, side: CGFloat) -> Path {
        let cell = side / 8
        let a = center(of: from, orientation: orientation, side: side)
        let b = center(of: to, orientation: orientation, side: side)
        let length = hypot(b.x - a.x, b.y - a.y)
        let d = CGPoint(x: (b.x - a.x) / length, y: (b.y - a.y) / length)
        let n = CGPoint(x: -d.y, y: d.x)

        // The outline is stroked with round joins below, which adds `rounding / 2` all round.
        let rounding = cell * 0.06
        let shaft = cell * 0.2 - rounding
        let headLength = cell * 0.42 - rounding
        let headWidth = cell * 0.52 - rounding
        let tip = CGPoint(x: b.x - d.x * rounding / 2, y: b.y - d.y * rounding / 2)
        let base = CGPoint(x: tip.x - d.x * headLength, y: tip.y - d.y * headLength)

        func p(_ origin: CGPoint, _ across: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + n.x * across, y: origin.y + n.y * across)
        }
        var outline = Path()
        outline.addLines([
            p(a, shaft / 2), p(base, shaft / 2), p(base, headWidth / 2),
            tip,
            p(base, -headWidth / 2), p(base, -shaft / 2), p(a, -shaft / 2),
        ])
        outline.closeSubpath()
        let rounded = outline.strokedPath(StrokeStyle(lineWidth: rounding, lineCap: .round, lineJoin: .round))
        return outline.union(rounded)
    }

    private static func center(of square: Square, orientation: Piece.Color, side: CGFloat) -> CGPoint {
        let r = BoardGeometry.rect(for: square, orientation: orientation, side: side)
        return CGPoint(x: r.midX, y: r.midY)
    }
}
