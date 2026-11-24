import SwiftUI
import ChessCore

/// Training interrupt: the move's class, a plain-words explanation and the three ways on.
/// It slides up in place of the action bar (`GameBoardScaffold`'s card) and never covers the
/// board. Opaque `surface` with a hairline edge; its bottom corners follow the screen's.
struct CoachCard: View {
    let verdict: Verdict
    var wording: MoveWording = .words
    let onTakeBack: () -> Void
    let onShowBest: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ClassPill(moveClass: verdict.classification)
            // The explanation is Pro; free users keep the verdict pill.
            ProGate(.trainingExplanations) {
                Text(explain(verdict, wording: wording))
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.text)
                    .fixedSize(horizontal: false, vertical: true)
            } locked: {
                LockedExplanation()
            }
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

/// The verdict's header in the coach's cards (Training interrupt, Review comment): the real
/// badge disc and the class name in its colour, sentence case ("?? Blunder").
struct ClassPill: View {
    let moveClass: MoveClass

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            MoveBadge(moveClass: moveClass)
            Text(moveClass.label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Color.moveClass(moveClass))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(moveClass.label)
    }
}
