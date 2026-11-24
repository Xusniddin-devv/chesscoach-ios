import SwiftUI
import ChessCore

/// The result panel over the final position, chess.com style: both players facing each other
/// with the score between them ("1 - 0", the reason small under it), each side's accuracy in
/// plain heavy type and its move classes as badge chips with counts, the key moment on a mini
/// board with one coach line, then Review game (primary), Rematch and New bot.
///
/// The bot's numbers come from the summary analysis that runs while the panel is up
/// (`PlayModel.analyzeFinishedGame`); until it lands the bot's side says so. Confetti on a
/// win only: subtle, once, behind the header. Opaque panel (content, not glass), one height
/// detent measured from its content; taller content scrolls.
struct GameOverSheet: View {
    let model: PlayModel
    let tier: RatingTier
    var wording: MoveWording = .words
    let saveFailed: Bool
    /// Review game was tapped and waits for the analysis to finish.
    let isOpeningReview: Bool
    let onReview: () -> Void
    let onRematch: () -> Void
    let onNewBot: () -> Void
    let onClose: () -> Void
    let onCloseWithoutSaving: () -> Void

    private var session: GameSession { model.session }
    private var user: Piece.Color { session.userColor }

    @State private var contentHeight: CGFloat = 0
    @State private var barHeight: CGFloat = 0

    private var detent: PresentationDetent {
        contentHeight > 0 ? .height(contentHeight + barHeight) : .large
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                accuracyRow
                    .padding(.top, DS.Spacing.l)
                chips
                    .padding(.top, DS.Spacing.sm)
                if session.hasEngineError && session.pendingGradeCount > 0 {
                    InlineErrorRow(message: "Analysis stopped.", actionTitle: "Retry") { session.retry() }
                        .padding(.top, DS.Spacing.m)
                }
                if saveFailed {
                    InlineErrorRow(message: "Couldn't save this game.", actionTitle: "Close anyway",
                                   action: onCloseWithoutSaving)
                        .padding(.top, DS.Spacing.m)
                }
                if let moment = model.summaryKeyMoment {
                    KeyMomentRow(verdict: moment, fen: model.fen(afterPly: moment.ply), orientation: user,
                                 text: ReviewModel.comment(on: moment, byUser: moment.mover == user,
                                                           botName: model.bot.name, wording: wording))
                        .padding(.top, DS.Spacing.l)
                        .id(moment.ply)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.top, 44)  // the close button sits above the avatars, not beside them
            .padding(.bottom, DS.Spacing.l)
            .animation(.smooth(duration: 0.35), value: model.summaryAnalysis != nil)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .overlay(alignment: .topTrailing) { closeButton }
        .safeAreaBar(edge: .bottom) { buttons }
        .presentationDetents([detent])
        .presentationBackground(DS.Color.surface)
        .presentationBackgroundInteraction(.enabled(upThrough: detent))
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 0) {
            PlayerColumn(avatar: tier.avatarAsset, name: "You", detail: tier.name, detailIsNumber: false,
                         isWinner: model.outcome == .won)
            VStack(spacing: DS.Spacing.xs) {
                Text(score)
                    .font(.system(size: 40, weight: .heavy).monospacedDigit())
                    .tracking(-1)
                    .foregroundStyle(DS.Color.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(reason)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 128)
            .padding(.top, 10)
            PlayerColumn(avatar: model.bot.avatarAsset, name: model.bot.name, detail: "\(model.bot.elo)",
                         detailIsNumber: true, isWinner: model.outcome == .lost)
        }
        .accessibilityElement(children: .combine)
        .background {
            if model.outcome == .won {
                ConfettiBurst()
                    .padding(.horizontal, -DS.Spacing.m)
                    .padding(.top, -44)
                    .clipped()
            }
        }
    }

    /// From the user's side: "1 - 0" when they won.
    private var score: String {
        switch model.outcome {
        case .won: "1 - 0"
        case .lost: "0 - 1"
        case .draw, nil: "½ - ½"
        }
    }

    /// One line that says who won and how: "You won by checkmate", "You resigned".
    private var reason: String {
        let how = model.endReason.lowercased()
        switch model.outcome {
        case .won: return "You won by \(how)"
        case .lost: return how == "you resigned" ? "You resigned" : "\(model.bot.name) won by \(how)"
        case .draw, nil: return "Draw by \(how)"
        }
    }

    // MARK: Accuracy and move classes

    private var accuracyRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            AccuracyNumber(value: model.summaryAccuracy(for: user), pending: session.pendingGradeCount > 0)
                .frame(maxWidth: .infinity)
            Text("Accuracy")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Color.textSecondary)
                .frame(width: 96)
            AccuracyNumber(value: model.summaryAccuracy(for: user.opposite), pending: model.summaryProgress != nil)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accuracyLabel)
    }

    private var accuracyLabel: String {
        func text(_ value: Double?) -> String {
            value.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "not ready"
        }
        return "Accuracy: you \(text(model.summaryAccuracy(for: user))), \(model.bot.name) \(text(model.summaryAccuracy(for: user.opposite)))"
    }

    private var chips: some View {
        HStack(alignment: .top, spacing: DS.Spacing.m) {
            ClassChips(counts: model.summaryCounts(for: user))
                .frame(maxWidth: .infinity)
            Group {
                if let progress = model.summaryProgress {
                    AnalysingLine(name: model.bot.name, progress: progress)
                } else {
                    ClassChips(counts: model.summaryCounts(for: user.opposite))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Buttons

    private var closeButton: some View {
        Button(action: onClose) {
            Image("Icons/close")
                .renderingMode(.template)
                .resizable()
                .frame(width: 14, height: 14)
                .foregroundStyle(DS.Color.textSecondary)
                .frame(width: 30, height: 30)
                .background(DS.Color.surface2, in: Circle())
                .padding(DS.Spacing.sm)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isSaving)
        .accessibilityLabel("Close")
    }

    private var buttons: some View {
        VStack(spacing: DS.Spacing.sm) {
            PrimaryButton(title: reviewTitle, action: onReview)
            HStack(spacing: DS.Spacing.sm) {
                SecondaryButton(title: "Rematch", action: onRematch)
                SecondaryButton(title: "New bot", action: onNewBot)
            }
        }
        .disabled(model.isSaving || isOpeningReview)
        .padding(.horizontal, DS.Spacing.m)
        .padding(.top, DS.Spacing.s)
        .padding(.bottom, DS.Spacing.s)
        .background(DS.Color.surface)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
    }

    private var reviewTitle: String {
        guard isOpeningReview, let progress = model.summaryProgress else { return "Review game" }
        return "Analysing… \(Int((progress * 100).rounded()))%"
    }
}

// MARK: Parts

/// One player: avatar on its board-dark tile (a 2 pt accent ring for the winner), name, and
/// the tier name or Elo under it.
private struct PlayerColumn: View {
    let avatar: String
    let name: String
    let detail: String
    let detailIsNumber: Bool
    let isWinner: Bool

    var body: some View {
        VStack(spacing: 6) {
            AvatarImage(asset: avatar, size: 64)
                .overlay {
                    if isWinner {
                        RoundedRectangle(cornerRadius: DS.Radius.medium + 4)
                            .strokeBorder(DS.Color.accent, lineWidth: 2)
                            .padding(-4)
                    }
                }
                .padding(.bottom, 4)
            Text(name)
                .font(DS.Font.headline)
                .foregroundStyle(DS.Color.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(detailIsNumber ? .system(size: 13, weight: .medium, design: .monospaced)
                                     : .system(size: 13, weight: .medium))
                .foregroundStyle(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// "96.3" in plain heavy type; a dash until it is known.
private struct AccuracyNumber: View {
    let value: Double?
    let pending: Bool

    var body: some View {
        Text(value.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "-")
            .font(.system(size: 34, weight: .heavy).monospacedDigit())
            .tracking(-1)
            .foregroundStyle(value == nil ? DS.Color.textSecondary : DS.Color.text)
            .contentTransition(.numericText())
            .animation(.smooth(duration: 0.4), value: value)
            .opacity(pending && value == nil ? 0.5 : 1)
    }
}

/// A side's move classes as chips: the real badge disc and the count, best first.
private struct ClassChips: View {
    let counts: [(moveClass: MoveClass, count: Int)]

    var body: some View {
        ChipFlow(spacing: 6) {
            ForEach(counts, id: \.moveClass) { item in
                HStack(spacing: 5) {
                    MoveBadge(moveClass: item.moveClass)
                        .scaleEffect(0.82)
                        .frame(width: 22, height: 22)
                    Text("\(item.count)")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(DS.Color.text)
                }
                .padding(.leading, 3)
                .padding(.trailing, 9)
                .padding(.vertical, 3)
                .background(DS.Color.background, in: Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.count) \(item.moveClass.label)")
            }
        }
    }
}

/// The bot's side while the summary analysis runs.
private struct AnalysingLine: View {
    let name: String
    let progress: Double

    var body: some View {
        VStack(spacing: 6) {
            Text("Checking \(name)'s moves")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
            ZStack(alignment: .leading) {
                Capsule().fill(DS.Color.background)
                Capsule().fill(DS.Color.textSecondary)
                    .frame(width: 72 * min(max(progress, 0), 1))
            }
            .frame(width: 72, height: 3)
            .animation(.smooth(duration: 0.3), value: progress)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Checking \(name)'s moves")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}

/// The game's turning point: the position after the move on a mini board with its badge,
/// "Key moment · move 14", the class, and the coach's line on it.
private struct KeyMomentRow: View {
    let verdict: Verdict
    let fen: String
    let orientation: Piece.Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MiniBoardView(fen: fen, highlight: Square(String(verdict.uci.dropFirst(2).prefix(2))),
                          badge: verdict.classification, orientation: orientation)
                .frame(width: 112, height: 112)
            VStack(alignment: .leading, spacing: 6) {
                Text("Key moment · move \((verdict.ply + 1) / 2)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Color.textSecondary)
                ClassPill(moveClass: verdict.classification)
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(DS.Color.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.sm)
        .background(DS.Color.background, in: RoundedRectangle(cornerRadius: DS.Radius.large))
        .accessibilityElement(children: .combine)
    }
}

/// Lays chips out in centred rows, wrapping to the next row when one is full.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(for: subviews, width: width)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.midX - row.width / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
