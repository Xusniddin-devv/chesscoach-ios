import SwiftUI
import SwiftData
import ChessCore

/// Home's "Today's plan": the current day of the training week, each task tappable, the goal
/// underneath. Tasks tick themselves off from what the user actually did today.
struct TodayPlanCard: View {
    let onPlay: (Bot) -> Void

    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    @Query(sort: \TrainingPlanRecord.created, order: .reverse) private var plans: [TrainingPlanRecord]
    @Query(sort: \UserProfile.updated, order: .reverse) private var profiles: [UserProfile]
    @Query private var progress: [PuzzleProgress]
    @Query private var lessons: [LessonProgress]
    @Query(TodayPlanCard.recentGames) private var games: [GameRecord]

    @State private var session: PuzzleSessionSetup?
    @State private var lesson: Lesson?
    @State private var paywall: ProFeature?

    static var recentGames: FetchDescriptor<GameRecord> {
        var d = FetchDescriptor<GameRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = 40
        return d
    }

    var body: some View {
        Group {
            if let plan = plans.first?.plan {
                if let index = plan.dayIndex(on: .now) {
                    card(plan: plan, day: plan.days[index])
                } else {
                    weekDone(plan)
                }
            }
        }
        .fullScreenCover(item: $session) { PuzzleSessionView(setup: $0) }
        .fullScreenCover(item: $lesson) { LessonView(lesson: $0, onNext: nil) }
        .sheet(item: $paywall) { PaywallView(feature: $0) }
    }

    private var dayStart: Date { Calendar.current.startOfDay(for: .now) }

    private func card(plan: TrainingPlan, day: PlanDay) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .center, spacing: DS.Spacing.sm) {
                DaySquare(index: day.index, emphasised: true, done: day.tasks.allSatisfy(isDone))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Today's plan")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                    Text(day.focus)
                        .font(DS.Font.title)
                        .foregroundStyle(DS.Color.text)
                }
                Spacer()
                Text("Day \(day.index + 1) of \(plan.days.count)")
                    .font(DS.Font.caption.monospacedDigit())
                    .foregroundStyle(DS.Color.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(day.tasks.enumerated()), id: \.element.id) { i, task in
                    if i > 0 { Divider().overlay(DS.Color.surface2).padding(.leading, 52) }
                    Button { start(task) } label: {
                        PlanTaskRow(task: task, done: isDone(task), showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let goal = goalLine {
                Divider().overlay(DS.Color.surface2)
                goal
            }
        }
        .padding(DS.Spacing.m)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
    }

    private func weekDone(_ plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            CoachBubble(pose: .pleased, text: "That's the week. Want the next one, built from what you played?",
                        avatarSize: 64, animated: false, fill: DS.Color.surface2)
            SecondaryButton(title: "Build next week") { rebuild(from: plan) }
        }
        .padding(DS.Spacing.m)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
    }

    /// "Goal 1200 by March · 260 to go".
    private var goalLine: AnyView? {
        guard let profile = profiles.first, let goal = profile.goalRating else { return nil }
        let toGo = max(0, goal - profile.currentRating)
        let by = profile.goalDate.map { " by \($0.formatted(.dateTime.month(.wide)))" } ?? ""
        return AnyView(
            HStack(spacing: 0) {
                Text("Goal ")
                Text(verbatim: "\(goal)\(by)").foregroundStyle(DS.Color.accent).fontWeight(.semibold)
                Text(toGo == 0 ? " · reached" : " · \(toGo) to go")
            }
            .font(DS.Font.subheadline.monospacedDigit())
            .foregroundStyle(DS.Color.textSecondary)
            .padding(.top, DS.Spacing.xs)
        )
    }

    // MARK: Done-ness (from what happened today)

    private func attemptedToday(_ row: PuzzleProgress) -> Bool { (row.lastAttempt ?? .distantPast) >= dayStart }

    private func isDone(_ task: PlanTask) -> Bool {
        switch task.kind {
        case .puzzles:
            let ids = Set(task.puzzleIds)
            return !ids.isEmpty && progress.filter { ids.contains($0.puzzleId) && attemptedToday($0) }.count >= ids.count
        case .ownMistakes:
            return progress.filter { $0.source == "blunder" && attemptedToday($0) }.count >= max(1, task.count)
        case .lesson:
            return task.lessonId.map { id in lessons.contains { $0.lessonId == id } } ?? false
        case .play:
            return games.contains { record in
                record.date >= dayStart && record.snapshot.map { $0.botId == task.botId && !$0.isImported } == true
            }
        }
    }

    // MARK: Launch

    private func start(_ task: PlanTask) {
        let remaining = PuzzleAllowance.remaining(progress, dailyId: PuzzleBank.daily(for: .now)?.id, isPro: entitlements.isPro)
        switch task.kind {
        case .puzzles:
            if remaining == 0 { paywall = .unlimitedPuzzles; return }
            let puzzles = task.puzzleIds.compactMap(PuzzleBank.puzzle(id:)).prefix(remaining ?? .max)
            session = PuzzleSessionSetup(kind: .practice, title: task.motif?.shortName ?? "Puzzles", puzzles: Array(puzzles),
                                         theme: task.motif.flatMap { PuzzleBank.themes(for: $0).first })
        case .ownMistakes:
            if remaining == 0 { paywall = .unlimitedPuzzles; return }
            let done = Set(progress.filter(attemptedToday).map(\.puzzleId))
            let own = games.compactMap(\.snapshot).filter { !$0.isFreeplay }.flatMap(BlunderPuzzles.from(snapshot:)).filter { !done.contains($0.id) }
            let queue = Array(own.prefix(min(max(1, task.count), remaining ?? .max)))
            guard !queue.isEmpty else { return }
            session = PuzzleSessionSetup(kind: .review, title: "Your mistakes", puzzles: queue,
                                         sources: Dictionary(queue.map { ($0.id, "blunder") }, uniquingKeysWith: { a, _ in a }))
        case .lesson:
            guard let id = task.lessonId, let l = LessonLibrary.lesson(id: id) else { return }
            if LessonAllowance.isLocked(l, isPro: entitlements.isPro) { paywall = .allLessons } else { lesson = l }
        case .play:
            guard let bot = Bot.all.first(where: { $0.id == task.botId }) else { return }
            onPlay(bot)
        }
    }

    private func rebuild(from old: TrainingPlan) {
        let snapshots = games.compactMap(\.snapshot).filter { !$0.isFreeplay }
        let report = WeaknessReport(snapshots)
        let rating = profiles.first?.currentRating ?? old.rating
        let own = snapshots.flatMap(BlunderPuzzles.from(snapshot:)).count
        let plan = TrainingPlan.make(weaknesses: report.top.isEmpty ? old.focus : report.top, rating: rating,
                                     ownMistakes: own, completedLessons: Set(lessons.map(\.lessonId)))
        ProfileStore.savePlan(plan, in: context)
    }
}
