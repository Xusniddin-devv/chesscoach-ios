import SwiftUI
import SwiftData
import ChessCore

/// Puzzles tab: the daily puzzle, the user's own mistakes due for review, and practice by
/// rating and theme. The streak sits in the navigation bar.
struct PuzzlesView: View {
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    @Query private var progress: [PuzzleProgress]
    @Query private var streaks: [StreakState]
    @Query(sort: \GameRecord.date, order: .reverse) private var games: [GameRecord]

    @AppStorage("puzzles.rating") private var rating = PlayerProfile.defaultRating
    @AppStorage("puzzles.theme") private var theme = ""
    @State private var session: PuzzleSessionSetup?
    @State private var blunders: [Puzzle] = []

    private static let sessionLength = 10

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    daily
                    mistakes
                    practice
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.l)
            }
            .background(DS.Color.background)
            .navigationTitle("Puzzles")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    StreakPill(count: streak.current(now: .now))
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .fullScreenCover(item: $session) { PuzzleSessionView(setup: $0) }
        .task(id: games.count) { blunders = Self.blunderPuzzles(from: games) }
        #if DEBUG
        // `-debugPuzzle daily|practice|mistakes` opens a solver session (screenshots).
        .task {
            switch UserDefaults.standard.string(forKey: "debugPuzzle") {
            case "daily":
                if let p = PuzzleBank.daily(for: .now) { session = PuzzleSessionSetup(kind: .daily, title: "Daily puzzle", puzzles: [p]) }
            case "practice":
                let pool = PuzzleBank.puzzles(band: practiceBand, theme: theme.isEmpty ? nil : theme)
                session = PuzzleSessionSetup(kind: .practice, title: "Practice", puzzles: Array(pool.prefix(5)))
            case "mistakes":
                let own = Self.blunderPuzzles(from: games)
                if !own.isEmpty {
                    session = PuzzleSessionSetup(kind: .review, title: "Your mistakes", puzzles: Array(own.prefix(5)),
                                                 sources: Dictionary(own.map { ($0.id, "blunder") }, uniquingKeysWith: { a, _ in a }))
                }
            default: break
            }
        }
        #endif
    }

    // MARK: Data

    private var streak: Streak {
        streaks.map(\.streak).max { ($0.lastDay ?? .distantPast, $0.count) < ($1.lastDay ?? .distantPast, $1.count) } ?? Streak()
    }

    private var progressById: [String: PuzzleProgress] {
        Dictionary(progress.map { ($0.puzzleId, $0) }, uniquingKeysWith: { a, b in a.reps >= b.reps ? a : b })
    }

    static func blunderPuzzles(from games: [GameRecord]) -> [Puzzle] {
        games.compactMap(\.snapshot).filter { !$0.isFreeplay }.flatMap(BlunderPuzzles.from(snapshot:))
    }

    /// Own mistakes not yet seen or due, then bank puzzles once failed and due again.
    private var dueReview: [(Puzzle, String)] {
        let now = Date.now
        let byId = progressById
        let own = blunders.filter { (byId[$0.id]?.due ?? .distantPast) <= now }.map { ($0, "blunder") }
        let failedBank = progress
            .filter { $0.source == "bank" && $0.lapses > 0 && $0.due <= now }
            .compactMap { PuzzleBank.puzzle(id: $0.puzzleId) }
            .map { ($0, "bank") }
        return own + failedBank
    }

    /// Puzzles the user may still start today; nil = unlimited (Pro). The daily one is always free.
    private var remainingToday: Int? {
        PuzzleAllowance.remaining(progress, dailyId: PuzzleBank.daily(for: .now)?.id, isPro: entitlements.isPro)
    }

    private func limited<T>(_ items: [T]) -> [T] {
        Array(items.prefix(min(Self.sessionLength, remainingToday ?? Self.sessionLength)))
    }

    private var nextReviewDate: Date? {
        let ids = Set(blunders.map(\.id))
        return progress.filter { ids.contains($0.puzzleId) || ($0.source == "bank" && $0.lapses > 0) }
            .map(\.due).filter { $0 > .now }.min()
    }

    // MARK: Daily

    @ViewBuilder
    private var daily: some View {
        if let puzzle = PuzzleBank.daily(for: .now) {
            let done = progressById[puzzle.id]?.lastSolved.map { Calendar.current.isDateInToday($0) } ?? false
            Button {
                session = PuzzleSessionSetup(kind: .daily, title: "Daily puzzle", puzzles: [puzzle])
            } label: {
                HStack(alignment: .top, spacing: DS.Spacing.m) {
                    MiniBoard(fen: puzzle.solvingFen ?? puzzle.fen, orientation: puzzle.solverColor)
                        .frame(width: 104, height: 104)
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        SectionLabel("Daily puzzle")
                        Text("\(puzzle.solverColor == .white ? "White" : "Black") to move")
                            .font(DS.Font.title)
                            .foregroundStyle(DS.Color.text)
                        HStack(spacing: DS.Spacing.xs) {
                            Text("Rating")
                            Text(puzzle.rating, format: .number.grouping(.never)).monospaced()
                        }
                        .font(DS.Font.subheadline)
                        .foregroundStyle(DS.Color.textSecondary)
                        Spacer(minLength: 0)
                        Text(done ? "Solved today" : "New today")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    Spacer(minLength: 0)
                    DoneRing(done: done)
                }
                .padding(DS.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.large))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Daily puzzle, \(done ? "solved today" : "not solved yet")")
        }
    }

    // MARK: Mistakes

    private var mistakes: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            SectionLabel("Your mistakes")
            let due = dueReview
            if !due.isEmpty, remainingToday == 0 {
                Text("\(due.count) \(due.count == 1 ? "position waits" : "positions wait") for you tomorrow, or now with Pro.")
                    .font(DS.Font.subheadline)
                    .foregroundStyle(DS.Color.textSecondary)
            } else if !due.isEmpty {
                Button {
                    let queue = limited(due)
                    session = PuzzleSessionSetup(kind: .review, title: "Your mistakes", puzzles: queue.map(\.0),
                                                 sources: Dictionary(queue.map { ($0.0.id, $0.1) }, uniquingKeysWith: { a, _ in a }))
                } label: {
                    HStack(spacing: DS.Spacing.m) {
                        Text(due.count, format: .number.grouping(.never))
                            .font(DS.Font.numeralLarge)
                            .foregroundStyle(DS.Color.text)
                            .frame(minWidth: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(due.count == 1 ? "Position to review" : "Positions to review")
                                .font(DS.Font.headline)
                                .foregroundStyle(DS.Color.text)
                            Text("Find the move you missed in your games.")
                                .font(DS.Font.subheadline)
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(DS.Spacing.m)
                    .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
                    .contentShape(RoundedRectangle(cornerRadius: DS.Radius.large))
                }
                .buttonStyle(.plain)
            } else {
                Text(emptyMistakesLine)
                    .font(DS.Font.subheadline)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
    }

    private var emptyMistakesLine: String {
        if let next = nextReviewDate {
            return "All caught up. Next review \(next.formatted(.relative(presentation: .named)))."
        }
        return blunders.isEmpty && games.isEmpty
            ? "Mistakes from your games turn into puzzles here."
            : "No mistakes to review. Nicely played."
    }

    // MARK: Practice

    private var practice: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            SectionLabel("Practice")
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rating").font(DS.Font.headline)
                        Text(available == 1 ? "1 puzzle left" : "\(available) puzzles left")
                            .font(DS.Font.subheadline.monospacedDigit())
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    Spacer()
                    Stepper(value: $rating, in: PuzzleBank.ratingRange.lowerBound...(PuzzleBank.ratingRange.upperBound - 100), step: 100) {
                        Text(rating, format: .number.grouping(.never))
                            .font(DS.Font.numeral)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .fixedSize()
                    .accessibilityLabel("Puzzle rating")
                    .accessibilityValue("\(rating)")
                }
                FlowLayout {
                    Chip(title: "Mixed", selected: theme.isEmpty) { theme = "" }
                    ForEach(PuzzleBank.practiceThemes, id: \.self) { key in
                        Chip(title: PuzzleBank.title(forTheme: key), selected: theme == key) { theme = key }
                    }
                }
            }
            .padding(DS.Spacing.m)
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
            if remainingToday == 0 {
                FreeLimitCard()
                    .padding(.top, DS.Spacing.s)
            } else {
                PrimaryButton(title: "Start practice", action: startPractice)
                    .padding(.top, DS.Spacing.s)
                if let left = remainingToday {
                    Text(left == 1 ? "1 free puzzle left today" : "\(left) free puzzles left today")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var available: Int {
        PuzzleBank.puzzles(band: practiceBand, theme: theme.isEmpty ? nil : theme, excluding: attempted).count
    }

    /// The stepper value is the band's centre: 800 → 700…899.
    private var practiceBand: Range<Int> { PuzzleBank.band(around: rating) }

    private var attempted: Set<String> { Set(progress.map(\.puzzleId)) }

    private func startPractice() {
        let chosen = theme.isEmpty ? nil : theme
        var pool = PuzzleBank.puzzles(band: practiceBand, theme: chosen, excluding: attempted)
        if pool.isEmpty { pool = PuzzleBank.puzzles(band: practiceBand, theme: chosen) }
        guard !pool.isEmpty else { return }
        let title = chosen.map(PuzzleBank.title(forTheme:)) ?? "Practice"
        session = PuzzleSessionSetup(kind: .practice, title: title, puzzles: limited(pool))
    }
}

/// Replaces Start practice once the free puzzles for today are used.
private struct FreeLimitCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Text("That's today's five")
                .font(DS.Font.headline)
                .foregroundStyle(DS.Color.text)
            Text("Five new ones tomorrow, and the daily puzzle is always free. Pro keeps the board open.")
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            UpgradeButton(.unlimitedPuzzles, title: "Keep solving with Pro")
                .padding(.top, DS.Spacing.xs)
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
    }
}
