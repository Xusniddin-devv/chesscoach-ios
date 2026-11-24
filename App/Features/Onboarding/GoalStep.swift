import SwiftUI
import ChessCore

/// Goal picker: scrub the rating distribution like an equalizer; the bars between today and
/// the target light up. Live "top N %", period chips and an honest estimated chance.
struct GoalStep: View {
    @Bindable var model: OnboardingModel
    let onSet: () -> Void

    var body: some View {
        OnboardingScaffold(model: model) {
            CoachBubble(pose: coachPose, text: coachText, avatarSize: 72)

            readout

            DistributionScrubber(distribution: model.distribution, current: model.rating, target: $model.target)

            HStack(spacing: DS.Spacing.s) {
                ForEach(GoalModel.periods, id: \.self) { m in
                    PeriodChip(title: m == 12 ? "1 year" : (m == 1 ? "1 month" : "\(m) months"),
                               selected: model.months == m) { model.months = m }
                }
            }
            .sensoryFeedback(.selection, trigger: model.months)

            chanceCard
        } footer: {
            PrimaryButton(title: "Set my goal", action: onSet)
        }
    }

    private var coachPose: CoachPose { model.chance >= 60 ? .pleased : (model.chance < 25 ? .thinking : .neutral) }

    private var coachText: String {
        "Pick a target along the players. I'll be honest about the odds."
    }

    private var readout: some View {
        let tier = RatingTier(rating: model.target)
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(alignment: .lastTextBaseline, spacing: DS.Spacing.sm) {
                Text(model.target, format: .number.grouping(.never))
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundStyle(DS.Color.text)
                    .contentTransition(.numericText(value: Double(model.target)))
                    .animation(.snappy(duration: 0.15), value: model.target)
                HStack(spacing: DS.Spacing.xs) {
                    PieceArt(kind: tier.piece, size: 30)
                    Text(tier.name)
                        .font(DS.Font.title)
                        .foregroundStyle(DS.Color.text)
                }
            }
            HStack(spacing: DS.Spacing.xs) {
                Text("Top \(Self.percent(model.distribution.topPercent(model.target))) of \(model.platform?.title ?? "chess.com") players")
                    .foregroundStyle(DS.Color.text)
                Text(verbatim: "· +\(model.target - model.rating) from today")
                    .foregroundStyle(DS.Color.textSecondary)
            }
            .font(DS.Font.subheadline.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    static func percent(_ p: Double) -> String {
        p < 1 ? String(format: "%.1f%%", p) : "\(Int(p.rounded()))%"
    }

    private var chanceCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.m) {
                Text("\(model.chance)%")
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DS.Color.text)
                    .contentTransition(.numericText(value: Double(model.chance)))
                    .animation(.snappy(duration: 0.2), value: model.chance)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated chance")
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.Color.text)
                    Text("An estimate from typical progress, not a promise")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            Text(GoalModel.verdict(chance: model.chance, months: model.months))
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Practice daily with Chess Coach and you can do it.")
                .font(DS.Font.body.weight(.semibold))
                .foregroundStyle(DS.Color.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
    }
}

/// Vertical bars per 50 points (share of players), the user's rating marked, the target
/// scrubbed with a finger. Haptic tick on every 50.
struct DistributionScrubber: View {
    let distribution: RatingDistribution
    let current: Int
    @Binding var target: Int

    private static let span = 1500
    private var window: ClosedRange<Int> {
        let width = RatingDistribution.bucketWidth
        var lo = max(RatingDistribution.range.lowerBound, (current / width) * width - 300)
        if lo + Self.span > RatingDistribution.range.upperBound { lo = RatingDistribution.range.upperBound - Self.span }
        return lo...(lo + Self.span)
    }

    var body: some View {
        let window = window
        let bars = distribution.buckets.filter { window.contains($0.rating) && $0.rating < window.upperBound }
        let peak = bars.map(\.share).max() ?? 1
        VStack(spacing: DS.Spacing.s) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let pitch = w / CGFloat(bars.count)
                let x: (Int) -> CGFloat = { CGFloat($0 - window.lowerBound) / CGFloat(Self.span) * w }
                ZStack(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(bars, id: \.rating) { bar in
                            let lit = bar.rating >= roundDown(current) && bar.rating < target
                            Capsule()
                                .fill(lit ? DS.Color.accent : (bar.rating < current ? DS.Color.text.opacity(0.28) : DS.Color.surface2))
                                .frame(width: max(2, pitch * 0.55),
                                       height: max(6, h * CGFloat(bar.share / peak) * 0.92))
                                .frame(width: pitch)
                                .animation(.snappy(duration: 0.12), value: lit)
                        }
                    }
                    // Today's rating.
                    Rectangle()
                        .fill(DS.Color.text)
                        .frame(width: 2, height: h)
                        .offset(x: x(current) - 1)
                    // Target handle.
                    VStack(spacing: 0) {
                        Circle().fill(DS.Color.accent).frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(DS.Color.background, lineWidth: 3))
                        Rectangle().fill(DS.Color.accent).frame(width: 2)
                    }
                    .frame(width: 16, height: h + 8)
                    .offset(x: x(target) - 8, y: 0)
                }
                .frame(width: w, height: h, alignment: .bottomLeading)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let raw = window.lowerBound + Int(value.location.x / w * CGFloat(Self.span))
                    let snapped = (raw + 25) / 50 * 50
                    let minimum = roundDown(current) + 50
                    target = min(max(snapped, minimum), window.upperBound)
                })
            }
            .frame(height: 132)

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    Text(verbatim: "You · \(current)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DS.Color.text)
                        .fixedSize()
                        .offset(x: max(0, min(w - 70, CGFloat(current - window.lowerBound) / CGFloat(Self.span) * w - 20)))
                    HStack {
                        Text(verbatim: String(window.lowerBound))
                        Spacer()
                        Text(verbatim: String(window.upperBound))
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DS.Color.textSecondary)
                    .offset(y: 16)
                }
            }
            .frame(height: 30)

            Text("Approximate distribution of active players")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sensoryFeedback(.selection, trigger: target)
        .accessibilityElement()
        .accessibilityLabel("Goal rating")
        .accessibilityValue("\(target)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: target = min(target + 50, window.upperBound)
            case .decrement: target = max(target - 50, roundDown(current) + 50)
            @unknown default: break
            }
        }
    }

    private func roundDown(_ r: Int) -> Int { r / 50 * 50 }
}

/// Equal-width period choice; selected = inverted like `Chip`.
private struct PeriodChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Font.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(selected ? DS.Color.ink : DS.Color.text)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(selected ? DS.Color.text : DS.Color.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
