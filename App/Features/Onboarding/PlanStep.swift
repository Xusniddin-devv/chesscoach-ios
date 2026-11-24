import SwiftUI
import ChessCore

/// The coach presents the week: day 1 open and actionable, days 2-7 as a file of squares.
struct PlanStep: View {
    let model: OnboardingModel
    let onStart: () -> Void

    var body: some View {
        OnboardingScaffold(model: model) {
            CoachBubble(pose: .pleased, text: coachText, avatarSize: 80)
            if let plan = model.plan {
                WeekView(plan: plan, today: 0)
            }
        } footer: {
            PrimaryButton(title: "Start day 1", action: onStart)
        }
    }

    private var coachText: String {
        guard let plan = model.plan else { return "Here's your week." }
        let focus = plan.focus.prefix(2).map { $0.shortName.lowercased() }.joined(separator: " and ")
        let pace = switch model.frequency {
        case .daily: "About fifteen minutes a day."
        case .weekends: "Short sessions, made for weekends."
        case .fewTimesAWeek, nil: "Ten minutes a day."
        }
        return "Here's your week: **\(focus)** first. \(pace)"
    }
}

/// The week in the path language of Home's Today's plan: today as three connected chunky
/// tokens (its practice steps, then the bot to play as the boss), then days 2-7 as a
/// vertical track of day tokens with the day's focus and what's in it. No tiles, no cards.
struct WeekView: View {
    let plan: TrainingPlan
    let today: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let day = plan.days.first(where: { $0.index == today }) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Today · \(day.focus)")
                        .font(.system(size: 20, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(DS.Color.text)
                    Spacer()
                    Text(weekday(day.index))
                        .font(DS.Font.subheadline.monospaced())
                        .foregroundStyle(DS.Color.textSecondary)
                }
                let steps = Self.steps(day, in: plan)
                PlanPath(steps: steps, state: { $0.id == steps.first?.id ? .current : .next }, action: { _ in })
                    .allowsHitTesting(false)
                    .padding(.top, DS.Spacing.sm)
            }
            VStack(spacing: 0) {
                let later = plan.days.filter { $0.index != today }
                ForEach(Array(later.enumerated()), id: \.element.id) { i, day in
                    HStack(alignment: .center, spacing: 14) {
                        DayToken(day: day)
                            .frame(width: 52, height: 64)
                            .background {
                                // The track joining the days: a full row's height, half at the ends.
                                let first = i == 0, last = i == later.count - 1
                                Rectangle().fill(DS.Color.surface2)
                                    .frame(width: 5, height: first || last ? 32 : 64)
                                    .offset(y: first ? 16 : last ? -16 : 0)
                                    .opacity(later.count > 1 ? 1 : 0)
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(weekday(day.index)) · \(day.focus)")
                                .font(DS.Font.headline)
                                .foregroundStyle(DS.Color.text)
                            Text(Self.summary(day))
                                .font(DS.Font.subheadline)
                                .foregroundStyle(DS.Color.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 64)
                }
            }
            .padding(.top, DS.Spacing.m)
        }
    }

    /// The day's path: up to two practice steps, then a game as the boss - the day's own,
    /// else the week's sparring bot.
    static func steps(_ day: PlanDay, in plan: TrainingPlan) -> [PlanTask] {
        let weekGame = plan.days.flatMap(\.tasks).first { $0.kind == .play }
        let play = day.tasks.first { $0.kind == .play }
            ?? weekGame.map { PlanTask(id: "boss-\(day.index)", kind: .play, title: $0.title, detail: $0.detail, botId: $0.botId) }
        let practice = day.tasks.filter { $0.kind != .play }.prefix(play == nil ? 3 : 2)
        return Array(practice) + (play.map { [$0] } ?? [])
    }

    static func summary(_ day: PlanDay) -> String {
        let puzzles = day.tasks.filter { $0.kind == .puzzles }.map(\.count).reduce(0, +)
        var parts: [String] = puzzles > 0 ? ["\(puzzles) puzzles"] : []
        for task in day.tasks {
            switch task.kind {
            case .puzzles: break
            case .ownMistakes: parts.append("\(task.count) of your mistakes")
            case .lesson, .play: parts.append(task.title)
            }
        }
        return parts.joined(separator: " · ")
    }

    private func weekday(_ index: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: index, to: plan.created) ?? plan.created
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
}

/// A later day on the week's track: a chunky round token with the day number in mono, or the
/// bot's avatar when the day ends in a game (that day's boss).
private struct DayToken: View {
    let day: PlanDay

    var body: some View {
        let bot = day.tasks.first { $0.kind == .play }.flatMap { task in Bot.all.first { $0.id == task.botId } }
        ZStack {
            Ellipse().fill(Color(hex: 0x0E1011)).frame(width: 48, height: 44).offset(y: 4)
            Ellipse().fill(bot == nil ? DS.Color.surface2 : DS.Color.boardDark).frame(width: 48, height: 44)
            if let bot {
                Image(bot.avatarAsset)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
            } else {
                Text(verbatim: "\(day.index + 1)")
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(DS.Color.text)
            }
        }
        .frame(height: 50)
        .accessibilityLabel("Day \(day.index + 1)")
    }
}
