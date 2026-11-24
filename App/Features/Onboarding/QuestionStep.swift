import SwiftUI
import ChessCore

/// A new player's three questions. The coach asks; the answers are three positions side by
/// side, each a board that shows what the answer means, picked with one tap.
struct QuestionStep: View {
    let model: OnboardingModel
    let index: Int

    private struct Option { let title: String; let detail: String; let fen: String }

    private var question: (ask: String, options: [Option]) {
        switch index {
        case 0:
            ("First: how well do you know the rules?", [
                Option(title: "Still learning the moves", detail: "The board looks busy", fen: "8/8/8/3N4/8/8/8/8 w - - 0 1"),
                Option(title: "I know the rules", detail: "Castling, en passant, the lot", fen: "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"),
                Option(title: "I know some tactics", detail: "Forks, pins, back ranks", fen: "r3k3/8/8/1N6/8/8/8/4K3 w - - 0 1"),
            ])
        case 1:
            ("Have you played full games?", [
                Option(title: "Not yet", detail: "This will be my first", fen: Rules.startFen),
                Option(title: "A few", detail: "With friends or an app", fen: "r1bq1rk1/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQ1RK1 w - - 0 6"),
                Option(title: "Lots, casually", detail: "No rating I'd show", fen: "8/5pk1/6p1/8/3R4/6P1/5PK1/3r4 w - - 0 40"),
            ])
        default:
            ("Last one. What do you want first?", [
                Option(title: "Win more games", detail: "Stop giving pieces away", fen: "4k3/8/8/3q4/8/2N5/8/4K3 w - - 0 1"),
                Option(title: "Better openings", detail: "Moves that make sense", fen: "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3"),
                Option(title: "Finish games", detail: "Checkmate patterns", fen: "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1"),
            ])
        }
    }

    var body: some View {
        let q = question
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if model.canGoBack {
                    BarButton(systemImage: "chevron.left", label: "Back", action: model.back)
                }
                Spacer()
                Text("\(index + 1) of 3")
                    .font(DS.Font.subheadline.monospacedDigit())
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(.horizontal, DS.Spacing.m)
            }
            .frame(height: 44)
            .padding(.horizontal, DS.Spacing.s)

            Spacer(minLength: DS.Spacing.l)

            CoachBubble(pose: index == 2 ? .pleased : .neutral, text: q.ask, avatarSize: 96)
                .padding(.horizontal, DS.Spacing.m)

            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                ForEach(Array(q.options.enumerated()), id: \.offset) { i, option in
                    AnswerCard(title: option.title, detail: option.detail, fen: option.fen,
                               selected: model.answers[index] == i) {
                        model.answer(index, i)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.top, DS.Spacing.l)

            Spacer(minLength: DS.Spacing.l)
            Spacer(minLength: 0)
        }
    }
}

/// A board with its answer underneath; the board gets an accent ring when picked.
private struct AnswerCard: View {
    let title: String
    let detail: String
    let fen: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                MiniBoard(fen: fen)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.small))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.small)
                            .strokeBorder(selected ? DS.Color.accent : .clear, lineWidth: 3)
                    }
                Text(title)
                    .font(DS.Font.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Color.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
