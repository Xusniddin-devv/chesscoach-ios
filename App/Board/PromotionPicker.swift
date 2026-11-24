import SwiftUI
import ChessCore

/// Sheet content for choosing a promotion piece. Shows the four pieces of the mover's
/// colour on a strip of board squares; there is no default choice (never auto-queen).
/// Presented as a system sheet, which is Liquid Glass on iOS 26.
struct PromotionPicker: View {
    let color: Piece.Color
    let onPick: (Piece.Kind) -> Void

    static let kinds: [Piece.Kind] = [.queen, .rook, .bishop, .knight]
    static let tile: CGFloat = 72
    /// Sheet height that fits the label and the strip.
    static let sheetHeight: CGFloat = 176

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("PROMOTE TO")
                .font(DS.Font.label)
                .tracking(DS.Font.labelTracking)
                .foregroundStyle(DS.Color.textSecondary)
            HStack(spacing: 0) {
                ForEach(Array(Self.kinds.enumerated()), id: \.element) { index, kind in
                    Button { onPick(kind) } label: {
                        PieceImage(piece: Piece(kind, color: color, square: .a1))
                            .padding(DS.Spacing.xs)
                            .frame(width: Self.tile, height: Self.tile)
                            .background(index.isMultiple(of: 2) ? DS.Color.boardLight : DS.Color.boardDark)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.name(kind))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.small))
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity)
    }

    static func name(_ kind: Piece.Kind) -> String {
        switch kind {
        case .queen: "Queen"
        case .rook: "Rook"
        case .bishop: "Bishop"
        case .knight: "Knight"
        case .king: "King"
        case .pawn: "Pawn"
        }
    }

    /// UCI promotion suffix.
    static func suffix(_ kind: Piece.Kind) -> String {
        switch kind {
        case .queen: "q"
        case .rook: "r"
        case .bishop: "b"
        case .knight: "n"
        case .king, .pawn: ""
        }
    }
}
