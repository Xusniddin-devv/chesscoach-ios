import SwiftUI
import ChessCore

/// "You're a Knight": the rating, the piece, the ladder of pieces, and what the games say.
struct RevealStep: View {
    let model: OnboardingModel
    @State private var shown = false

    private var tier: RatingTier { RatingTier(rating: model.rating) }

    var body: some View {
        OnboardingScaffold(model: model) {
            CoachBubble(pose: .pleased, text: coachText, avatarSize: 80)

            hero

            TierLadder(current: tier)

            if let report = model.report, model.platform != nil {
                findings(report)
            } else if let answers = model.newPlayerAnswers {
                startingPoints(answers)
            }
        } footer: {
            PrimaryButton(title: "Set a goal") { model.go(.goal) }
        }
        .onAppear { withAnimation(.spring(duration: 0.8, bounce: 0.25).delay(0.15)) { shown = true } }
        .sensoryFeedback(.success, trigger: shown)
    }

    private var coachText: String {
        if model.platform == nil {
            return tier == .pawn ? "Every king started as a pawn. Let's get you moving." : "You're a \(tier.name). A good place to start."
        }
        switch tier {
        case .pawn: return "You're a Pawn. Pawns become queens. Let's walk you up the board."
        case .king: return "You're a King. I'll keep up. Let's find what still costs you points."
        default: return "You're a \(tier.name). Solid. Let's make you a \(tier.next?.name ?? tier.name)."
        }
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(sourceLabel)
                    .font(DS.Font.subheadline)
                    .foregroundStyle(DS.Color.textSecondary)
                Text(model.rating, format: .number.grouping(.never))
                    .font(.system(size: 84, weight: .bold, design: .monospaced))
                    .foregroundStyle(DS.Color.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: Double(shown ? model.rating : 0)))
                Text(tier.name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(DS.Color.text)
                if let toNext = RatingTier.pointsToNext(from: model.rating), let next = tier.next {
                    Text("\(toNext) points to \(next.name)")
                        .font(DS.Font.subheadline.monospacedDigit())
                        .foregroundStyle(DS.Color.textSecondary)
                        .padding(.top, DS.Spacing.xs)
                }
            }
            Spacer(minLength: 0)
            PieceArt(kind: tier.piece, size: 168)
                .scaleEffect(shown ? 1 : 0.6, anchor: .bottom)
                .opacity(shown ? 1 : 0)
                .offset(x: 10)
        }
    }

    private var sourceLabel: String {
        guard let platform = model.platform, let key = model.foundProfile?.currentRatingKey else {
            return model.platform == nil ? "Your starting rating" : "Your rating"
        }
        return "\(platform.title) \(key)"
    }

    // MARK: Findings

    @ViewBuilder
    private func findings(_ report: WeaknessReport) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("What keeps costing you")
                .font(DS.Font.title)
                .foregroundStyle(DS.Color.text)
            if let top = report.weaknesses.first {
                WeaknessHero(weakness: top, games: report.gamesAnalysed, orientation: userColor(for: top))
                ForEach(Array(report.weaknesses.dropFirst().prefix(2).enumerated()), id: \.offset) { _, w in
                    WeaknessRow(weakness: w, games: report.gamesAnalysed)
                }
            } else {
                Text("No habit repeats across your games. We'll train broad tactics and see what shows up.")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            if let accuracy = report.averageAccuracy {
                HStack(spacing: DS.Spacing.xs) {
                    Text("Average accuracy")
                    Text(Int(accuracy.rounded()), format: .number).monospaced().foregroundStyle(DS.Color.text)
                    Text("across \(report.gamesAnalysed) games")
                }
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.top, DS.Spacing.xs)
            }
        }
    }

    private func userColor(for weakness: WeaknessReport.Weakness) -> Piece.Color {
        model.games.first { $0.id == weakness.exampleGameId }?.userColor ?? .white
    }

    private func startingPoints(_ answers: NewPlayerAnswers) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Where we'll start")
                .font(DS.Font.title)
                .foregroundStyle(DS.Color.text)
            ForEach(answers.weaknesses, id: \.self) { motif in
                HStack(spacing: DS.Spacing.sm) {
                    Text(motif.shortName)
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.Color.text)
                    Spacer()
                    Text(TrainingPlan.lessonTrack(for: motif).title)
                        .font(DS.Font.subheadline)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                .padding(.vertical, DS.Spacing.s)
                Divider().overlay(DS.Color.surface2)
            }
        }
    }
}

/// The six tiers as six pieces on a rank; the user's piece stands up, the rest are shadows.
struct TierLadder: View {
    let current: RatingTier

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RatingTier.allCases, id: \.self) { tier in
                VStack(spacing: DS.Spacing.xs) {
                    PieceArt(kind: tier.piece, size: tier == current ? 44 : 32)
                        .opacity(tier == current ? 1 : (tier < current ? 0.55 : 0.22))
                        .frame(height: 46, alignment: .bottom)
                    Rectangle()
                        .fill(tier == current ? DS.Color.accent : (tier < current ? DS.Color.textSecondary : DS.Color.surface2))
                        .frame(height: 3)
                    Text(verbatim: String(tier.floor))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(tier == current ? DS.Color.text : DS.Color.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, DS.Spacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tier \(current.name), of Pawn, Knight, Bishop, Rook, Queen, King")
    }
}

/// The top habit with the position where it cost the most, the bad move marked.
private struct WeaknessHero: View {
    let weakness: WeaknessReport.Weakness
    let games: Int
    let orientation: Piece.Color

    static func example(_ motif: Motif, _ v: Verdict) -> String {
        let n = v.facts.moveNumber
        let to = String(v.uci.dropFirst(2).prefix(2))
        let best = String(v.bestMove.dropFirst(2).prefix(2))
        switch motif {
        case .hangingPiece: return "Move \(n): nothing guarded the piece you put on [\(to)]."
        case .allowedFork: return "Move \(n): after [\(to)], one reply hit two of your pieces."
        case .missedCapture: return best.count == 2 ? "Move \(n): you went to [\(to)] while [\(best)] was free." : "Move \(n): a free piece went untaken."
        case .allowedMate: return "Move \(n): [\(to)] opened the door to mate."
        case .missedMate: return best.count == 2 ? "Move \(n): you went to [\(to)]; mate started on [\(best)]." : "Move \(n): mate was on the board."
        case .openingPrinciple: return "Move \(n): the queen came out before the pieces."
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.m) {
            if let example = weakness.example {
                MiniBoard(fen: example.facts.fenBefore, orientation: orientation)
                    .overlay { MoveMark(uci: example.uci, bestUci: example.bestMove, orientation: orientation) }
                    .frame(width: 120, height: 120)
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(weakness.motif.habit)
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let example = weakness.example {
                    CoachText(Self.example(weakness.motif, example))
                        .font(DS.Font.subheadline)
                        .foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DS.Spacing.xs)
                Tally(count: weakness.count, games: games)
            }
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
    }
}

private struct WeaknessRow: View {
    let weakness: WeaknessReport.Weakness
    let games: Int

    var body: some View {
        HStack {
            Text(weakness.motif.habit)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.text)
            Spacer(minLength: DS.Spacing.s)
            Tally(count: weakness.count, games: games, compact: true)
        }
        .padding(.vertical, DS.Spacing.sm)
        .padding(.horizontal, DS.Spacing.xs)
        .overlay(alignment: .bottom) { Divider().overlay(DS.Color.surface2) }
    }
}

/// Tally marks: one red dash per time it happened (up to 10), then the count.
struct Tally: View {
    let count: Int
    let games: Int
    var compact = false

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            HStack(spacing: 3) {
                ForEach(0..<min(count, compact ? 5 : 6), id: \.self) { _ in
                    Capsule().fill(DS.Color.danger).frame(width: 10, height: 4)
                }
            }
            if !compact {
                Text(verbatim: "\(count)× in \(games) games")
                    .lineLimit(1)
                    .fixedSize()
                    .font(DS.Font.caption.monospacedDigit())
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
        .accessibilityLabel("\(count) times in \(games) games")
    }
}

/// A blunder badge on the destination square of `uci`, over a MiniBoard.
struct MoveMark: View {
    let uci: String
    /// The better move, ringed in accent.
    var bestUci: String? = nil
    let orientation: Piece.Color

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            if uci.count >= 4 {
                let to = Square(String(uci.dropFirst(2).prefix(2)))
                let from = Square(String(uci.prefix(2)))
                let r = BoardGeometry.rect(for: to, orientation: orientation, side: side)
                let f = BoardGeometry.rect(for: from, orientation: orientation, side: side)
                ZStack {
                    if let best = bestUci, best.count >= 4, best != uci {
                        let b = BoardGeometry.rect(for: Square(String(best.dropFirst(2).prefix(2))), orientation: orientation, side: side)
                        Rectangle().strokeBorder(DS.Color.accent, lineWidth: max(2, b.width * 0.12))
                            .frame(width: b.width, height: b.height).position(x: b.midX, y: b.midY)
                    }
                    Rectangle().fill(DS.Color.danger.opacity(0.45)).frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
                    Rectangle().fill(DS.Color.danger.opacity(0.25)).frame(width: f.width, height: f.height).position(x: f.midX, y: f.midY)
                    MoveBadge(moveClass: .blunder)
                        .scaleEffect(max(0.55, r.width / 26))
                        .position(x: r.maxX - 2, y: r.minY + 2)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
