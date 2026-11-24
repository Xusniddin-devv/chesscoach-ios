import SwiftUI
import SwiftData
import ChessCore

/// Home's "Today's plan" as a short Duolingo-style path: three chunky tokens joined by a
/// track - the day's puzzles, its lesson, and the bot to play as the boss token (its avatar)
/// - each done / current / next from what the player actually did today, and one chunky
/// Start for the current step. Without a plan (onboarding skipped) the path is the daily
/// puzzle, the next lesson and the ladder's next bot.
struct TodayPlanCard: View {
    let nextBot: Bot
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
        let steps = Self.steps(plans.first?.plan, defaults: defaultTasks, boss: nextBot)
        let current = steps.first { !isDone($0) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                ScreenSectionTitle("Today's plan")
                Spacer()
                if let plan = plans.first?.plan, let i = plan.dayIndex(on: .now) {
                    Text("Day \(i + 1) of \(plan.days.count)")
                        .font(DS.Font.subheadline.monospacedDigit())
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            PlanPath(steps: steps, state: { isDone($0) ? .done : $0.id == current?.id ? .current : .next },
                     action: start)
                .padding(.top, DS.Spacing.m)
            if let current {
                Button("Start · \(current.title)") { start(current) }
                    .buttonStyle(ChunkyButtonStyle())
                    .lineLimit(1)
                    .padding(.top, DS.Spacing.m)
            } else if let plan = plans.first?.plan, plan.dayIndex(on: .now) == nil {
                Button("Build next week") { rebuild(from: plan) }
                    .buttonStyle(ChunkyButtonStyle())
                    .padding(.top, DS.Spacing.m)
            } else {
                Text("Today's plan is done. Come back tomorrow, or play a game for fun.")
                    .font(DS.Font.subheadline)
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(.top, DS.Spacing.m)
            }
        }
        .fullScreenCover(item: $session) { PuzzleSessionView(setup: $0) }
        .fullScreenCover(item: $lesson) { LessonView(lesson: $0, onNext: nil) }
        .sheet(item: $paywall) { PaywallView(feature: $0) }
    }

    /// Three steps: up to two practice tasks of the day, then a game as the boss - the day's
    /// own game, else the ladder's next bot.
    static func steps(_ plan: TrainingPlan?, defaults: [PlanTask], boss: Bot) -> [PlanTask] {
        guard let plan, let i = plan.dayIndex(on: .now) else { return defaults }
        let tasks = plan.days[i].tasks
        // The day's game, else the week's sparring bot, else the ladder's next bot.
        let weekGame = plan.days.flatMap(\.tasks).first { $0.kind == .play }
        let play = tasks.first { $0.kind == .play }
            ?? weekGame.map { PlanTask(id: "boss-\(i)", kind: .play, title: $0.title, detail: $0.detail, botId: $0.botId) }
            ?? PlanTask(id: "boss-\(boss.id)", kind: .play, title: "Play \(boss.name)", detail: "Next on the ladder", botId: boss.id)
        let practice = tasks.filter { $0.kind != .play }.prefix(2)
        return practice.isEmpty ? defaults : Array(practice) + [play]
    }

    /// No plan yet: the daily puzzle, the next lesson, the ladder's next bot.
    private var defaultTasks: [PlanTask] {
        var tasks: [PlanTask] = []
        if let daily = PuzzleBank.daily(for: .now) {
            tasks.append(PlanTask(id: "default-daily", kind: .puzzles, title: "Daily puzzle",
                                  detail: "One puzzle a day", puzzleIds: [daily.id]))
        }
        let done = Set(lessons.map(\.lessonId))
        if let next = LessonTrack.allCases.lazy.compactMap({ LessonLibrary.lessons(in: $0).first { !done.contains($0.id) } }).first {
            tasks.append(PlanTask(id: "default-lesson", kind: .lesson, title: next.title, detail: "Lesson", lessonId: next.id))
        }
        tasks.append(PlanTask(id: "default-play", kind: .play, title: "Play \(nextBot.name)", detail: "Next on the ladder", botId: nextBot.id))
        return tasks
    }

    /// What the coach says the day is: "five puzzles from your games, then Cadet".
    static func hook(_ steps: [PlanTask]) -> String? {
        guard let first = steps.first else { return nil }
        let start = first.title.prefix(1).lowercased() + first.title.dropFirst()
        if let boss = steps.last, boss.kind == .play, let bot = Bot.all.first(where: { $0.id == boss.botId }), steps.count > 1 {
            return "\(start), then **\(bot.name)**"
        }
        return String(start)
    }

    private var dayStart: Date { Calendar.current.startOfDay(for: .now) }

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
            let own = PuzzlesView.blunderPuzzles(from: games).filter { !done.contains($0.id) }
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
        let snapshots = GameRecord.unique(games).compactMap(\.snapshot).filter { !$0.isFreeplay }
        let report = WeaknessReport(snapshots)
        let rating = profiles.first?.currentRating ?? old.rating
        let own = PuzzlesView.blunderPuzzles(from: games).count
        let plan = TrainingPlan.make(weaknesses: report.top.isEmpty ? old.focus : report.top, rating: rating,
                                     ownMistakes: own, completedLessons: Set(lessons.map(\.lessonId)))
        ProfileStore.savePlan(plan, in: context)
    }
}

/// A day as a short path: its steps as chunky tokens joined by a track (accent behind done
/// steps). Home's Today's plan and onboarding's week both draw days this way.
struct PlanPath: View {
    let steps: [PlanTask]
    let state: (PlanTask) -> StepToken.State
    let action: (PlanTask) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, task in
                StepToken(task: task, bot: task.kind == .play ? Bot.all.first { $0.id == task.botId } : nil,
                          state: state(task),
                          leadingLit: i > 0 && state(steps[i - 1]) == .done, hasLeading: i > 0,
                          trailingLit: state(task) == .done, hasTrailing: i < steps.count - 1) { action(task) }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// The Icons8 glyph for a step's kind.
    static func glyph(_ kind: PlanTask.Kind) -> String {
        switch kind {
        case .puzzles: "puzzle"
        case .ownMistakes: "review"
        case .lesson: "lesson"
        case .play: "play"
        }
    }
}

/// One step of the day's path: a chunky round token (the bot's avatar for the game - the
/// day's boss), the track to its neighbours (accent once the step before is done), and its
/// name under it.
struct StepToken: View {
    enum State { case done, current, next }

    let task: PlanTask
    let bot: Bot?
    let state: State
    let leadingLit: Bool
    let hasLeading: Bool
    let trailingLit: Bool
    let hasTrailing: Bool
    let action: () -> Void
    @SwiftUI.State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let size: CGFloat = 66

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            ZStack {
                // The track: half to each side, under the token.
                HStack(spacing: 0) {
                    Capsule().fill(leadingLit ? DS.Color.accent : DS.Color.surface2).frame(height: 6).opacity(hasLeading ? 1 : 0)
                    Capsule().fill(trailingLit ? DS.Color.accent : DS.Color.surface2).frame(height: 6).opacity(hasTrailing ? 1 : 0)
                }
                .padding(.horizontal, -2)
                Button(action: action) { face }
                    .buttonStyle(StepTokenStyle(face: faceColor, edge: edgeColor))
                    .background {
                        if state == .current {
                            Circle()
                                .strokeBorder(DS.Color.accent.opacity(0.55), lineWidth: 4)
                                .frame(width: Self.size + 20, height: Self.size + 20)
                                .scaleEffect(pulse ? 1.07 : 0.97)
                                .opacity(pulse ? 0.35 : 0.9)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if state == .done {
                            IconImage("check", size: 11)
                                .foregroundStyle(DS.Color.accent)
                                .frame(width: 22, height: 22)
                                .background(DS.Color.background, in: Circle())
                                .overlay(Circle().strokeBorder(DS.Color.accent, lineWidth: 2))
                                .offset(x: 2, y: -2)
                        }
                    }
            }
            .frame(height: Self.size + 24)
            Text(task.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(state == .next ? DS.Color.textSecondary : DS.Color.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 110)
        }
        .onAppear {
            guard state == .current, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title), \(state == .done ? "done" : state == .current ? "next up" : "later")")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var face: some View {
        if let bot {
            Image(bot.avatarAsset)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 50, height: 50)
        } else {
            IconImage(PlanPath.glyph(task.kind), size: 28)
                .foregroundStyle(state == .next ? DS.Color.text.opacity(0.5) : state == .current || state == .done ? DS.Color.onAccent : DS.Color.text)
        }
    }

    private var faceColor: Color {
        if bot != nil { return DS.Color.boardDark }
        return state == .next ? DS.Color.surface2 : DS.Color.accent
    }

    private var edgeColor: Color {
        if bot != nil { return Color(hex: 0x4F5554) }
        return state == .next ? Color(hex: 0x0E1011) : DS.Color.accentPressed
    }
}

private struct StepTokenStyle: ButtonStyle {
    let face: Color
    let edge: Color

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .frame(width: 66, height: 62)
            .background(face, in: Ellipse())
            .background(alignment: .bottom) {
                Ellipse().fill(edge).frame(height: 62).offset(y: pressed ? 0 : 5)
            }
            .offset(y: pressed ? 5 : 0)
            .animation(.snappy(duration: 0.12), value: pressed)
    }
}
