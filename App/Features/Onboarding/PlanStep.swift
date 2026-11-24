import SwiftUI
import ChessCore

/// The coach presents the week: day 1 open and actionable, days 2–7 as a file of squares.
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
        return "Here's your week: **\(focus)** first. Ten minutes a day."
    }
}

/// Day `today` open as a card, the other days as rows with a board-square day number.
struct WeekView: View {
    let plan: TrainingPlan
    let today: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if let day = plan.days.first(where: { $0.index == today }) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    HStack(spacing: DS.Spacing.sm) {
                        DaySquare(index: day.index, emphasised: true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Today")
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.textSecondary)
                            Text(day.focus)
                                .font(DS.Font.title)
                                .foregroundStyle(DS.Color.text)
                        }
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(day.tasks.enumerated()), id: \.element.id) { i, task in
                            if i > 0 { Divider().overlay(DS.Color.surface2).padding(.leading, 52) }
                            PlanTaskRow(task: task, done: false)
                        }
                    }
                }
                .padding(DS.Spacing.m)
                .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
            }
            VStack(spacing: 0) {
                ForEach(plan.days.filter { $0.index != today }) { day in
                    HStack(spacing: DS.Spacing.sm) {
                        DaySquare(index: day.index)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.focus)
                                .font(DS.Font.headline)
                                .foregroundStyle(DS.Color.text)
                            Text(Self.summary(day))
                                .font(DS.Font.subheadline)
                                .foregroundStyle(DS.Color.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text(weekday(day.index))
                            .font(DS.Font.caption.monospaced())
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    .padding(.vertical, DS.Spacing.s)
                    .padding(.horizontal, DS.Spacing.m)
                }
            }
        }
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

/// The day number on a board square: odd days light, even days dark, like walking up a file.
struct DaySquare: View {
    let index: Int
    var emphasised = false
    var done = false

    var body: some View {
        let light = index % 2 == 0
        Text("\(index + 1)")
            .font(.system(size: emphasised ? 17 : 15, weight: .semibold, design: .monospaced))
            .foregroundStyle(DS.Color.ink)
            .frame(width: emphasised ? 40 : 32, height: emphasised ? 40 : 32)
            .background(light ? DS.Color.boardLight : DS.Color.boardDark, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                if emphasised {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(DS.Color.accent, lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if done {
                    Circle().fill(DS.Color.accent).frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(DS.Color.background, lineWidth: 2))
                        .offset(x: 3, y: -3)
                }
            }
            .accessibilityLabel("Day \(index + 1)")
    }
}

/// One task: its Icons8 glyph (no tile), title, one line; done = struck through with the
/// Icons8 check in accent.
struct PlanTaskRow: View {
    let task: PlanTask
    let done: Bool
    var showsChevron = false

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Glyph(name: Self.glyph(task.kind), size: 22)
                .foregroundStyle(done ? DS.Color.textSecondary : DS.Color.text)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(DS.Font.headline)
                    .foregroundStyle(done ? DS.Color.textSecondary : DS.Color.text)
                    .strikethrough(done, color: DS.Color.textSecondary)
                    .lineLimit(1)
                Text(task.detail)
                    .font(DS.Font.subheadline)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Spacing.s)
            if done {
                Glyph(name: "check", size: 18).foregroundStyle(DS.Color.accent)
            } else if showsChevron {
                Glyph(name: "forward", size: 14).foregroundStyle(DS.Color.textSecondary)
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    static func glyph(_ kind: PlanTask.Kind) -> String {
        switch kind {
        case .puzzles: "puzzle"
        case .ownMistakes: "review"
        case .lesson: "lesson"
        case .play: "play"
        }
    }
}
