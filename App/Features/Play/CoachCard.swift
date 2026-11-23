import SwiftUI
import ChessCore

/// Training interrupt: the move's class, a plain-words explanation and the three ways on.
/// It slides up in place of the action bar (`GameBoardScaffold`'s card) and never covers the
/// board. Opaque `surface` with a hairline edge; its bottom corners follow the screen's.
struct CoachCard: View {
    let verdict: Verdict
    let onTakeBack: () -> Void
    let onShowBest: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ClassPill(moveClass: verdict.classification)
            Text(explain(verdict, wording: .words))
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Spacing.sm) {
                SecondaryButton(title: "Take back", action: onTakeBack)
                PrimaryButton(title: "Show best", action: onShowBest)
            }
            Button("Continue", action: onContinue)
                .font(DS.Font.headline)
                .foregroundStyle(DS.Color.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, -DS.Spacing.xs)
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface, in: Self.shape)
        .overlay(Self.shape.stroke(DS.Color.surface2, lineWidth: 1))
    }

    private static var shape: ConcentricRectangle {
        ConcentricRectangle(uniformTopCorners: .fixed(DS.Radius.large),
                            uniformBottomCorners: .concentric(minimum: .fixed(DS.Radius.large)))
    }
}

/// "?? BLUNDER": class fill, ink text, label style.
struct ClassPill: View {
    let moveClass: MoveClass

    var body: some View {
        Text("\(moveClass.glyph) \(moveClass.label.uppercased())")
            .font(DS.Font.label)
            .tracking(DS.Font.labelTracking)
            .foregroundStyle(DS.Color.moveClassGlyph(moveClass))
            .padding(.horizontal, DS.Spacing.s)
            .padding(.vertical, DS.Spacing.xs)
            .background(DS.Color.moveClass(moveClass), in: RoundedRectangle(cornerRadius: DS.Radius.small))
            .accessibilityLabel(moveClass.label)
    }
}
