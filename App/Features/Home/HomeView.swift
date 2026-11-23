import SwiftUI
import SwiftData
import ChessCore

/// Greeting, the one accent "Play a bot" card, and the last five games.
struct HomeView: View {
    private enum Route: Hashable {
        case botPicker
        case review(GameRecord)
    }

    @Query(HomeView.recentGames) private var records: [GameRecord]
    @State private var path: [Route] = []
    @State private var game: PlaySetup?

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
                }
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
        .task {
            DebugLaunch.apply(path: { path = [.botPicker] }, play: { game = $0 })
            if DebugReview.requested, let latest = records.first { path = [.review(latest)] }
        }
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
            SectionLabel("Recent games")
            // An unreadable record is skipped here; `GameRecord.snapshot` logs it.
            let games = records.compactMap { record in record.snapshot.map { (record, $0) } }
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
