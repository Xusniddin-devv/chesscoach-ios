import SwiftUI
import SwiftData
import ChessCore

/// Greeting with the streak; the play entry — the one accent "Play a bot" card next to a
/// quiet analysis-board tile; today's plan led by the coach (flat, no card); the last five
/// games (bots and imports; analysis-board lines are not games and stay out of the list).
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
    @State private var path: [Route] = []
    @State private var game: PlaySetup?
    /// Where the result panel sends the player once the game's cover has closed.
    @State private var exit: PlayView.Exit?

    static let recentCount = 5

    /// The newest readable games against the bots, at most `recentCount`; analysis-board lines
    /// and unreadable records are left out. `records` newest first.
    static func recentGames(_ records: [GameRecord]) -> [(record: GameRecord, snapshot: GameSnapshot)] {
        Array(records.lazy
            .compactMap { record in record.snapshot.map { (record: record, snapshot: $0) } }
            .filter { !$0.snapshot.isFreeplay }
            .prefix(recentCount))
    }

    /// The latest analysis-board line, to continue from Home.
    static func latestFreeplay(_ records: [GameRecord]) -> (record: GameRecord, snapshot: GameSnapshot)? {
        records.lazy
            .compactMap { record in record.snapshot.map { (record: record, snapshot: $0) } }
            .first { $0.snapshot.isFreeplay }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let line = Self.latestFreeplay(allRecords)
                    HStack(spacing: DS.Spacing.sm) {
                        NavigationLink(value: Route.botPicker) { PlayCard(next: BotLadder(records: allRecords, hub: hub).next ?? .suggested) }
                            .buttonStyle(.plain)
                        NavigationLink(value: Route.freeplay(line?.record)) { AnalysisBoardTile(line: line?.snapshot) }
                            .buttonStyle(.plain)
                            .frame(width: 124)
                    }
                    .frame(height: 164)
                    .padding(.top, DS.Spacing.s)
                    TodayPlanCard { bot in
                        game = PlaySetup(bot: bot, mode: .training, color: .random)
                    }
                    .padding(.top, 30)
                    recent
                        .padding(.top, 30)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, DS.Spacing.l)
            }
            .contentMargins(.bottom, DS.Spacing.xl, for: .scrollContent)
            .scrollIndicators(.hidden)
            .background(DS.Color.background)
            .navigationTitle(Self.greeting(for: .now))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { StreakPill(count: streak) }
                    .sharedBackgroundVisibility(.hidden)
            }
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
            // Under the cover, go back to Home so "Done" lands on the new game in the list.
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

    private var streak: Int {
        let best = streaks.map(\.streak).max { ($0.lastDay ?? .distantPast, $0.count) < ($1.lastDay ?? .distantPast, $1.count) }
        return (best ?? Streak()).current(now: .now)
    }

    static func greeting(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    @ViewBuilder
    private var recent: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            ScreenSectionTitle("Recent games")
            // An unreadable record is skipped here; `GameRecord.snapshot` logs it.
            let games = Self.recentGames(allRecords).map { ($0.record, $0.snapshot) }
            if games.isEmpty {
                Text("Your games will show up here.")
                    .font(DS.Font.subheadline)
                    .foregroundStyle(DS.Color.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(games.enumerated()), id: \.element.0.id) { index, game in
                        if index > 0 {
                            Divider().overlay(DS.Color.surface2).padding(.leading, DS.Spacing.m + 32 + DS.Spacing.sm)
                        }
                        NavigationLink(value: Route.review(game.0)) {
                            GameRow(snapshot: game.1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
            }
        }
    }
}

/// The analysis board's entry next to the Play card: a quiet `surface` tile (the Play card
/// stays the one accent) with the current line's position and what tapping does.
private struct AnalysisBoardTile: View {
    let line: GameSnapshot?

    private var fen: String {
        guard let line else { return Rules.startFen }
        return Rules.fen(startFen: line.startFen, moves: line.moves) ?? line.startFen
    }

    private var subline: String {
        guard let line, !line.moves.isEmpty else { return "Both sides" }
        let moves = (line.moves.count + 1) / 2
        return "Continue · \(moves) \(moves == 1 ? "move" : "moves")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MiniBoardView(fen: fen)
                .frame(width: 92, height: 92)
            Spacer(minLength: 0)
            Text("Analysis board")
                .font(DS.Font.subheadline.weight(.semibold))
                .foregroundStyle(DS.Color.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(subline)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.large))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(line.map { _ in "Analysis board, \(subline)" } ?? "Analysis board")
    }
}

/// The single accent surface on Home.
private struct PlayCard: View {
    let next: Bot

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Play a bot")
                    .font(DS.Font.title)
                HStack(spacing: 0) {
                    Text("Next up: \(next.name) · ")
                    Text(next.elo, format: .number.grouping(.never)).monospaced()
                }
                .font(DS.Font.subheadline)
                .opacity(0.85)
            }
            .foregroundStyle(DS.Color.onAccent)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Image(next.avatarAsset)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 84, height: 84)
                .accessibilityHidden(true)
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.large))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.large))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
