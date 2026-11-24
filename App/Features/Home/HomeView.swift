import SwiftUI
import SwiftData
import ChessCore

/// Greeting, the one accent "Play a bot" card, and the last five games.
struct HomeView: View {
    private enum Route: Hashable { case botPicker }

    @Query(HomeView.recentGames) private var records: [GameRecord]
    @State private var path: [Route] = []
    @State private var game: PlaySetup?
    @State private var showingSettings = false  // feat/settings-paywall; moves to Profile after the merge

    static var recentGames: FetchDescriptor<GameRecord> {
        var descriptor = FetchDescriptor<GameRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 5
        return descriptor
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    NavigationLink(value: Route.botPicker) { PlayCard(next: .suggested) }
                        .buttonStyle(.plain)
                    TodayPlanCard { bot in
                        game = PlaySetup(bot: bot, mode: .training, color: .random)
                    }
                    recent
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.l)
            }
            .background(DS.Color.background)
            .navigationTitle(Self.greeting(for: .now))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsSheet() }
            .navigationDestination(for: Route.self) { _ in
                BotPickerView { game = $0 }
            }
        }
        .fullScreenCover(item: $game) { setup in
            PlayView(setup: setup)
        }
        .onChange(of: game) { _, started in
            // Under the cover, go back to Home so "Done" lands on the new game in the list.
            if started != nil { var t = Transaction(); t.disablesAnimations = true; withTransaction(t) { path = [] } }
        }
        #if DEBUG
        .task { DebugLaunch.apply(path: { path = [.botPicker] }, play: { game = $0 }) }
        .task { if ["settings", "paywall"].contains(UserDefaults.standard.string(forKey: "debugOpen")) { showingSettings = true } }
        #endif
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
            Text("Recent games")
                .font(DS.Font.title)
                .foregroundStyle(DS.Color.text)
                .accessibilityAddTraits(.isHeader)
            // An unreadable record is skipped here; `GameRecord.snapshot` logs it.
            let games = records.compactMap { record in record.snapshot.map { (record.id, $0) } }
            if games.isEmpty {
                Text("Your games will show up here.")
                    .font(DS.Font.subheadline)
                    .foregroundStyle(DS.Color.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(games.enumerated()), id: \.element.0) { index, game in
                        if index > 0 {
                            Divider().overlay(DS.Color.surface2).padding(.leading, DS.Spacing.m + 32 + DS.Spacing.sm)
                        }
                        RecentGameRow(snapshot: game.1)
                    }
                }
                .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
            }
        }
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

/// "vs Pip", when, and the result from the user's side.
private struct RecentGameRow: View {
    let snapshot: GameSnapshot

    private var bot: Bot? { snapshot.isImported ? nil : Bot.all.first { $0.id == snapshot.botId } }

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            if let bot {
                AvatarTile(bot: bot, size: 32)
            } else if snapshot.isImported {
                Glyph(name: snapshot.source == ImportPlatform.lichess.rawValue ? "lichess" : "chesscom", size: 18)
                    .foregroundStyle(DS.Color.text)
                    .frame(width: 32, height: 32)
                    .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: AvatarTile.radius(32)))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("vs \(bot?.name ?? snapshot.opponentName ?? snapshot.botId)")
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.text)
                Text(when)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(outcome.score).font(DS.Font.numeral).foregroundStyle(DS.Color.text)
                Text(outcome.word).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    private var when: String {
        let date = snapshot.date
        let mode = snapshot.source.flatMap(ImportPlatform.init(rawValue:))?.title
            ?? (snapshot.mode == .training ? "Training" : "Silent")
        let day: String
        if Calendar.current.isDateInToday(date) {
            day = date.formatted(date: .omitted, time: .shortened)
        } else if Calendar.current.isDateInYesterday(date) {
            day = "Yesterday"
        } else {
            day = date.formatted(.dateTime.month(.abbreviated).day())
        }
        return "\(day) · \(mode)"
    }

    private var outcome: (score: String, word: String) {
        switch snapshot.result {
        case .draw: return ("½–½", "Draw")
        case .ongoing: return ("–", "Unfinished")
        case .whiteWins, .blackWins:
            let won = (snapshot.result == .whiteWins) == (snapshot.userColor == .white)
            return won ? ("1–0", "Won") : ("0–1", "Lost")
        }
    }
}
