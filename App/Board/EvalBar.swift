import SwiftUI
import ChessCore

/// 6 pt vertical evaluation bar. The light segment is always White and sits on White's
/// side of the board (`EvalBarLayout`). Flat colours, no gradient.
struct EvalBar: View {
    /// Evaluation from White's point of view, in centipawns (mates already mapped by `toCp`).
    let whiteCp: Double
    let orientation: Piece.Color

    static let width: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let white = geo.size.height * EvalBarLayout.whiteFraction(whiteCp: whiteCp)
            ZStack(alignment: EvalBarLayout.whiteAnchoredAtBottom(orientation: orientation) ? .bottom : .top) {
                DS.Color.surface2
                DS.Color.text.frame(height: white)
            }
        }
        .frame(width: Self.width)
        .clipShape(Capsule())
        .animation(.smooth(duration: 0.4), value: whiteCp)
        .accessibilityElement()
        .accessibilityLabel("Evaluation")
        .accessibilityValue(Self.spoken(whiteCp))
    }

    static func spoken(_ cp: Double) -> String {
        let pawns = (abs(cp) / 100).formatted(.number.precision(.fractionLength(1)))
        if abs(cp) < 5 { return "Equal" }
        return "\(cp > 0 ? "White" : "Black") better by \(pawns)"
    }
}
