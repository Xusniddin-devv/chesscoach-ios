import SwiftUI
import ChessCore

/// The result over the final position: result word, reason, score line, the user's accuracy
/// in an accent arc, move counts, and Play again / Done. Confetti on a win only.
struct GameOverSheet: View {
    let model: PlayModel
    let saveFailed: Bool
    let onPlayAgain: () -> Void
    let onDone: () -> Void
    let onCloseWithoutSaving: () -> Void

    private var session: GameSession { model.session }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                HStack(alignment: .center, spacing: DS.Spacing.m) {
                    header
                    Spacer(minLength: 0)
                    AccuracyArc(accuracy: model.accuracy, pending: session.pendingGradeCount)
                }
                if session.hasEngineError && session.pendingGradeCount > 0 {
                    InlineErrorRow(message: "Analysis stopped.", actionTitle: "Retry") { session.retry() }
                }
                if saveFailed {
                    InlineErrorRow(message: "Couldn't save this game.", actionTitle: "Close anyway",
                                   action: onCloseWithoutSaving)
                }
                stats
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.top, DS.Spacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: DS.Spacing.sm) {
                PrimaryButton(title: "Play again", action: onPlayAgain)
                SecondaryButton(title: "Done", action: onDone)
            }
            .disabled(model.isSaving)
            .padding(.horizontal, DS.Spacing.m)
            .padding(.bottom, DS.Spacing.s)
        }
        .overlay(alignment: .top) {
            if model.outcome == .won {
                ConfettiBurst()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(resultWord)
                .font(DS.Font.largeTitle)
                .foregroundStyle(DS.Color.text)
            Text(model.endReason)
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
            Text("You \(score) \(model.bot.name)")
                .font(DS.Font.numeral)
                .foregroundStyle(DS.Color.text)
                .padding(.top, DS.Spacing.s)
        }
    }

    private var resultWord: String {
        switch model.outcome {
        case .won: "You won"
        case .lost: "You lost"
        case .draw, nil: "Draw"
        }
    }

    private var score: String {
        switch model.outcome {
        case .won: "1 – 0"
        case .lost: "0 – 1"
        case .draw, nil: "½ – ½"
        }
    }

    private var stats: some View {
        VStack(spacing: 0) {
            StatRow(label: "Best moves", value: model.count([.brilliant, .great, .best]))
            Divider().overlay(DS.Color.surface2)
            StatRow(label: "Mistakes", value: model.count([.mistake, .miss]))
            Divider().overlay(DS.Color.surface2)
            StatRow(label: "Blunders", value: model.count([.blunder]))
        }
        .padding(.horizontal, DS.Spacing.m)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
    }
}

private struct StatRow: View {
    let label: String
    let value: Int

    var body: some View {
        HStack {
            Text(label).font(DS.Font.body).foregroundStyle(DS.Color.text)
            Spacer()
            Text("\(value)").font(DS.Font.numeral).foregroundStyle(DS.Color.text)
        }
        .padding(.vertical, DS.Spacing.sm)
        .accessibilityElement(children: .combine)
    }
}

/// Accuracy numeral inside a flat 270° accent arc (stroke only). While grades are still
/// running the numeral is a dash and the arc stays empty.
private struct AccuracyArc: View {
    let accuracy: Double?
    let pending: Int

    private static let sweep = 0.75
    private static let size: CGFloat = 128
    private static let line: CGFloat = 8

    var body: some View {
        ZStack {
            arc(1).stroke(DS.Color.surface2, style: StrokeStyle(lineWidth: Self.line, lineCap: .round))
            arc((accuracy ?? 0) / 100)
                .stroke(DS.Color.accent, style: StrokeStyle(lineWidth: Self.line, lineCap: .round))
                .animation(.smooth(duration: 0.6), value: accuracy)
            VStack(spacing: 2) {
                Text(accuracy.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")
                    .font(DS.Font.numeralLarge)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(DS.Color.text)
                    .contentTransition(.numericText())
                Text(pending > 0 ? "Finishing analysis…" : "ACCURACY")
                    .font(pending > 0 ? DS.Font.caption : DS.Font.label)
                    .tracking(pending > 0 ? 0 : DS.Font.labelTracking)
                    .foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: Self.size - 2 * Self.line - 8)
        }
        .frame(width: Self.size, height: Self.size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Accuracy")
        .accessibilityValue(accuracy.map { "\($0.formatted()) percent" } ?? "Finishing analysis")
    }

    /// A 270° track open at the bottom, filled clockwise from the lower left.
    private func arc(_ fraction: Double) -> some Shape {
        Circle()
            .trim(from: 0, to: Self.sweep * min(max(fraction, 0), 1))
            .rotation(.degrees(135))
    }
}
