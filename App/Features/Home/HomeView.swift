import SwiftUI
import SwiftData
import ChessCore

/// Greeting, the one accent "Play a bot" card, the analysis board, and the last five games
/// against the bots (analysis-board lines are not games: they stay out of the list).
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
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    NavigationLink(value: Route.botPicker) { PlayCard(next: BotLadder(records: allRecords, hub: hub).next ?? .suggested) }
                        .buttonStyle(.plain)
                    let line = Self.latestFreeplay(allRecords)
                    NavigationLink(value: Route.freeplay(line?.record)) { AnalysisBoardCard(line: line?.snapshot) }
                        .buttonStyle(.plain)
                    recent
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.l)
            }
            .background(DS.Color.background)
            .navigationTitle(Self.greeting(for: .now))
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
            SectionLabel("Recent games")
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

/// The analysis board's entry: a quiet `surface` card (the Play card stays the one accent),
/// the current line's position on a mini board, and what continuing means.
private struct AnalysisBoardCard: View {
    let line: GameSnapshot?

    private var fen: String {
        guard let line else { return Rules.startFen }
        return Rules.fen(startFen: line.startFen, moves: line.moves) ?? line.startFen
    }

    private var subline: String {
        guard let line, !line.moves.isEmpty else { return "Move both sides. Every move gets a grade." }
        let moves = (line.moves.count + 1) / 2
        let count = "\(moves) \(moves == 1 ? "move" : "moves")"
        return "Continue · " + (line.openingName.map { "\($0) · \(count)" } ?? count)
    }

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Analysis board")
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.text)
                Text(subline)
                    .font(DS.Font.subheadline)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            MiniBoardView(fen: fen)
                .frame(width: 64, height: 64)
        }
        .padding(DS.Spacing.m)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.large))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
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
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
        }
        .padding(DS.Spacing.m)
        .frame(height: 132)
        .background(DS.Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.large))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.large))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
