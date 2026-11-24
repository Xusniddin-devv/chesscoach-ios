import SwiftUI
import SwiftData
import ChessCore

/// Home in the coach's voice: a compact header (streak, rating → goal), the coach saying
/// what today is about from real data (last game, top habit, the plan), today's plan as a
/// three-token path ending in the bot to play, and "Continue": the analysis board and the
/// recent games as a filmstrip of final positions. The ladder stays one tap away.
struct HomeView: View {
    private enum Route: Hashable {
        case botPicker
        case review(GameRecord)
        /// The analysis board: the latest saved line, or a fresh board.
        case freeplay(GameRecord?)
    }

    /// Every saved game, newest first: the recent list, the ladder's next bot on the Play
    /// card, and the analysis board's latest line.
    @Query(sort: \GameRecord.date, order: .reverse) private var allRecords: [GameRecord]
    @Environment(\.modelContext) private var context
    @Environment(EngineHub.self) private var hub
    @Query private var streaks: [StreakState]
    @Query(sort: \UserProfile.updated, order: .reverse) private var profiles: [UserProfile]
    @Query(sort: \TrainingPlanRecord.created, order: .reverse) private var plans: [TrainingPlanRecord]
    @Query private var lessons: [LessonProgress]
    @State private var path: [Route] = []
    @State private var game: PlaySetup?
    /// Where the result panel sends the player once the game's cover has closed.
    @State private var exit: PlayView.Exit?

    static let recentCount = 5

    /// The newest readable games against the bots, at most `recentCount`; analysis-board lines
    /// and unreadable records are left out. `records` newest first.
    static func recentGames(_ records: [GameRecord]) -> [(record: GameRecord, snapshot: GameSnapshot)] {
        Array(GameRecord.unique(records).lazy
            .compactMap { record in record.snapshot.map { (record: record, snapshot: $0) } }
            .filter { !$0.snapshot.isFreeplay }
            .prefix(recentCount))
    }

    /// The latest analysis-board line, to continue from Home.
    static func latestFreeplay(_ records: [GameRecord]) -> (record: GameRecord, snapshot: GameSnapshot)? {
        GameRecord.unique(records).lazy
            .compactMap { record in record.snapshot.map { (record: record, snapshot: $0) } }
            .first { $0.snapshot.isFreeplay }
    }

    var body: some View {
        let profile = ProfileModel(records: allRecords, platformRating: profiles.first?.platformRating)
        let nextBot = BotLadder(records: allRecords, profile: profile).next ?? .suggested
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HomeHeader(streak: streak, rating: profile.rating ?? profiles.first.map(\.currentRating),
                               hasEstimate: profile.rating != nil || profiles.first != nil,
                               goal: profiles.first?.goalRating, goalDate: profiles.first?.goalDate,
                               played: profile.finishedCount)
                    coach(profile, nextBot: nextBot)
                        .padding(.top, DS.Spacing.m)
                    TodayPlanCard(nextBot: nextBot) { bot in
                        game = PlaySetup(bot: bot, mode: .training, color: .random)
                    }
                    .padding(.top, DS.Spacing.l)
                    NavigationLink(value: Route.botPicker) {
                        HStack(spacing: DS.Spacing.s) {
                            Image(nextBot.avatarAsset)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 28, height: 28)
                                .background(DS.Color.boardDark, in: RoundedRectangle(cornerRadius: 7))
                            Text("Sparring ladder · next up \(nextBot.name)")
                                .font(DS.Font.subheadline.weight(.semibold))
                                .foregroundStyle(DS.Color.text)
                            Spacer()
                            IconImage("forward", size: 13).foregroundStyle(DS.Color.textSecondary)
                        }
                        .padding(.vertical, DS.Spacing.sm)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, DS.Spacing.s)
                    continueSection(profile)
                        .padding(.top, 26)
                }
                .padding(.horizontal, 20)
            }
            .contentMargins(.bottom, 96, for: .scrollContent)
            .scrollIndicators(.hidden)
            .autoSyncRefreshable()
            .background(DS.Color.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .botPicker: BotPickerView { game = $0 }
                case .review(let record): ReviewView(record: record)
                case .freeplay(let record): FreeplayView(record: record)
                }
            }
        }
        .fullScreenCover(item: $game, onDismiss: routeExit) { setup in
            PlayView(setup: setup) { exit = $0 }
        }
        .onChange(of: game) { _, started in
            // Under the cover, go back to Home so "Done" lands on Home with the new game.
            if started != nil { var t = Transaction(); t.disablesAnimations = true; withTransaction(t) { path = [] } }
        }
        #if DEBUG
        .task {
            DebugLaunch.apply(path: { path = [.botPicker] }, play: { game = $0 })
            if DebugReview.requested, let record = DebugReview.pick(Self.recentGames(allRecords).map(\.record)) {
                path = [.review(record)]
            }
            if DebugFreeplay.requested { path = [.freeplay(UserDefaults.standard.string(forKey: "debugFreeplay") == "resume" ? Self.latestFreeplay(allRecords)?.record : nil)] }
        }
        #endif
    }

    private var streak: Int {
        let best = streaks.map(\.streak).max { ($0.lastDay ?? .distantPast, $0.count) < ($1.lastDay ?? .distantPast, $1.count) }
        return (best ?? Streak()).current(now: .now)
    }

    // MARK: Coach

    private func coach(_ profile: ProfileModel, nextBot: Bot) -> some View {
        let steps = TodayPlanCard.steps(plans.first?.plan, defaults: [], boss: nextBot)
        let line = Self.coachLine(profile: profile, hook: TodayPlanCard.hook(steps), nextBot: nextBot)
        return HStack(alignment: .bottom, spacing: 0) {
            CoachAvatar(pose: line.pose, size: 118)
                .padding(.leading, -16)
            CoachText(line.text)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DS.Color.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.Spacing.m)
                .padding(.vertical, DS.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BubbleShape(tailY: 22).fill(DS.Color.surface))
                .padding(.bottom, 26)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach: \(CoachText.plain(line.text))")
    }

    /// The coach's line from real data: the last game, the habit that keeps costing points,
    /// and what today is ("five puzzles from your games, then **Cadet**").
    static func coachLine(profile: ProfileModel, hook: String?, nextBot: Bot) -> (text: String, pose: CoachPose) {
        guard let last = profile.games.first else {
            return ("I'm your coach. Today: the daily puzzle, a first lesson, then a game with **\(nextBot.name)**. I'll learn how you play.", .neutral)
        }
        var parts: [String] = []
        var pose = CoachPose.neutral
        let when = Calendar.current.isDateInToday(last.snapshot.date) ? "earlier today"
            : Calendar.current.isDateInYesterday(last.snapshot.date) ? "yesterday" : "last time"
        switch last.outcome {
        case .win?: parts.append("You beat **\(last.botName)** \(when)."); pose = .pleased
        case .loss?: parts.append("**\(last.botName)** got you \(when).")
        case .draw?: parts.append("A draw with **\(last.botName)** \(when).")
        case nil: parts.append("Your game with **\(last.botName)** is still open.")
        }
        // A synced (or imported) game, once analysed: its mistakes are puzzles now.
        if let line = Self.importedPuzzlesLine(last) { parts.append(line) }
        if let habit = profile.weaknesses.first {
            let recent = profile.games.prefix(5).filter { game in
                ProfileModel.userVerdicts(game.snapshot).contains { $0.motifs.contains(habit.motif) }
            }.count
            if recent > 1 {
                parts.append("\(habit.motif.headline) - in \(recent) of your last \(min(5, profile.games.count)) games.")
                pose = .concerned
            }
        }
        if let hook { parts.append("Now: \(hook).") }
        return (parts.joined(separator: " "), pose)
    }

    /// "One mistake in it is now a puzzle." for an analysed chess.com / Lichess game.
    static func importedPuzzlesLine(_ game: ProfileModel.Game) -> String? {
        guard game.snapshot.isImported, game.snapshot.analysis != nil else { return nil }
        let count = game.record.blunderPuzzles.count
        switch count {
        case 0: return nil
        case 1: return "One mistake in it is now a puzzle."
        default: return "\(count) mistakes in it are now puzzles."
        }
    }

    // MARK: Continue

    @ViewBuilder
    private func continueSection(_ profile: ProfileModel) -> some View {
        let line = Self.latestFreeplay(allRecords)
        ScreenSectionTitle("Continue")
            .padding(.bottom, DS.Spacing.sm)
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 10) {
                NavigationLink(value: Route.freeplay(line?.record)) { AnalysisThumb(line: line?.snapshot) }
                    .buttonStyle(.plain)
                ForEach(profile.games.prefix(12)) { game in
                    NavigationLink(value: Route.review(game.record)) { GameThumb(game: game) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -20)
        if profile.games.isEmpty {
            Text("Your games show up here, ready to review.")
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.top, DS.Spacing.s)
        }
    }

    /// Review game → the saved game in Review; New bot → the bot ladder.
    private func routeExit() {
        defer { exit = nil }
        switch exit {
        case .review(let id):
            var descriptor = FetchDescriptor<GameRecord>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let record = try? context.fetch(descriptor).first { path = [.review(record)] }
        case .newBot:
            path = [.botPicker]
        case .home, nil:
            break
        }
    }
}

/// Streak on the left; rating → goal with a thin progress line on the right. One line each,
/// no tiles.
private struct HomeHeader: View {
    let streak: Int
    let rating: Int?
    let hasEstimate: Bool
    let goal: Int?
    let goalDate: Date?
    let played: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 0) {
                    if streak > 0 {
                        Text(verbatim: "\(streak)").monospacedDigit().foregroundStyle(DS.Color.accent)
                        Text(" day streak").foregroundStyle(DS.Color.text)
                    } else {
                        Text("No streak yet").foregroundStyle(DS.Color.textSecondary)
                    }
                }
                .font(.system(size: 17, weight: .bold))
                Spacer()
                Group {
                    if let rating, let goal {
                        HStack(spacing: 0) {
                            Text(verbatim: "\(rating) → \(goal)").monospacedDigit().foregroundStyle(DS.Color.text)
                            if let goalDate { Text(" by \(goalDate.formatted(.dateTime.month(.wide)))").foregroundStyle(DS.Color.textSecondary) }
                        }
                    } else if let rating, hasEstimate {
                        Text(verbatim: "\(rating) · \(RatingTier(rating: rating).name)").monospacedDigit().foregroundStyle(DS.Color.text)
                    } else {
                        Text("\(played) of 3 games to your rating").foregroundStyle(DS.Color.textSecondary)
                    }
                }
                .font(.system(size: 15, weight: .semibold))
            }
            if let rating, let goal {
                GeometryReader { geo in
                    let start = Double(max(0, goal - 700))
                    let value = min(max((Double(rating) - start) / max(1, Double(goal) - start), 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.Color.surface2)
                        Capsule().fill(DS.Color.accent).frame(width: max(4, geo.size.width * value))
                    }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            }
        }
        .padding(.top, DS.Spacing.s)
        .accessibilityElement(children: .combine)
    }
}

/// The analysis board as the first frame of the Continue strip: its position on a mini
/// board, like the game frames next to it.
private struct AnalysisThumb: View {
    let line: GameSnapshot?

    private var fen: String {
        guard let line else { return Rules.startFen }
        return Rules.fen(startFen: line.startFen, moves: line.moves) ?? line.startFen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            MiniBoardView(fen: fen)
                .frame(width: GameThumb.side, height: GameThumb.side)
                .overlay(alignment: .topLeading) {
                    Text(line?.moves.isEmpty == false ? "Board" : "New")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.Color.text)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(DS.Color.background, in: RoundedRectangle(cornerRadius: 5))
                        .padding(6)
                }
            HStack(spacing: 6) {
                IconImage("edit", size: 14).foregroundStyle(DS.Color.textSecondary)
                Text("Analysis board")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Color.text)
                    .lineLimit(1)
            }
            .frame(width: GameThumb.side, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Analysis board")
        .accessibilityAddTraits(.isButton)
    }
}
