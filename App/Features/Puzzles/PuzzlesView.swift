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
    static let margin: CGFloat = 20

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    daily
                    mistakes
                    practice
                }
                .padding(.horizontal, Self.margin)
                .padding(.bottom, DS.Spacing.xl)
            }
            // Clear the floating tab bar.
            .contentMargins(.bottom, DS.Spacing.xl, for: .scrollContent)
            .scrollIndicators(.hidden)
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
                session = PuzzleSessionSetup(kind: .practice, title: theme.isEmpty ? "Practice" : PuzzleBank.title(forTheme: theme),
                                             puzzles: Array(pool.prefix(5)), theme: theme.isEmpty ? nil : theme)
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

    /// The day's puzzle as the screen's hero: a big board of the position to solve, the side
    /// to move as the title, the rating in mono. No card around it.
    @ViewBuilder
    private var daily: some View {
        if let puzzle = PuzzleBank.daily(for: .now) {
            let done = progressById[puzzle.id]?.lastSolved.map { Calendar.current.isDateInToday($0) } ?? false
            Button {
                session = PuzzleSessionSetup(kind: .daily, title: "Daily puzzle", puzzles: [puzzle])
            } label: {
                HStack(alignment: .top, spacing: DS.Spacing.m) {
                    MiniBoard(fen: puzzle.solvingFen ?? puzzle.fen, orientation: puzzle.solverColor)
                        .frame(width: 164, height: 164)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Daily puzzle")
                            .font(DS.Font.subheadline)
                            .foregroundStyle(DS.Color.textSecondary)
                        Text("\(puzzle.solverColor == .white ? "White" : "Black") to move")
                            .font(.system(size: 26, weight: .bold))
                            .tracking(-0.4)
                            .foregroundStyle(DS.Color.text)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 4) {
                            Text("Rated")
                            Text(verbatim: String(puzzle.rating)).monospacedDigit()
                        }
                        .font(DS.Font.subheadline)
                        .foregroundStyle(DS.Color.textSecondary)
                        Spacer(minLength: 0)
                        if done {
                            HStack(spacing: 6) {
                                IconImage("check", size: 16).foregroundStyle(DS.Color.accent)
                                Text("Solved today").foregroundStyle(DS.Color.text)
                            }
                            .font(DS.Font.subheadline.weight(.semibold))
                        } else {
                            Text("Solve it")
                                .font(DS.Font.headline)
                                .foregroundStyle(DS.Color.accent)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(height: 164)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, DS.Spacing.s)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Daily puzzle, \(puzzle.solverColor == .white ? "White" : "Black") to move, \(done ? "solved today" : "not solved yet")")
        }
    }

    // MARK: Mistakes

    /// Own mistakes as a filmstrip of the real positions (the user's side at the bottom):
    /// tap one to start there.
    @ViewBuilder
    private var mistakes: some View {
        let due = dueReview
        ScreenSectionTitle("From your games", trailing: due.isEmpty ? nil : String(due.count))
            .padding(.top, 30)
            .padding(.bottom, DS.Spacing.sm)
        if !due.isEmpty, remainingToday == 0 {
            Text("\(due.count) \(due.count == 1 ? "position waits" : "positions wait") for you tomorrow, or now with Pro.")
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
        } else if !due.isEmpty {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(due.prefix(12).enumerated()), id: \.element.0.id) { index, item in
                        Button { startReview(due, at: index) } label: {
                            MiniBoard(fen: item.0.solvingFen ?? item.0.fen, orientation: item.0.solverColor)
                                .frame(width: 96, height: 96)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Position \(index + 1)")
                    }
                }
                .padding(.horizontal, Self.margin)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Self.margin)
            Text("Positions where a better move was there. Find it this time.")
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.top, DS.Spacing.sm)
        } else {
            Text(emptyMistakesLine)
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
        }
    }

    private func startReview(_ due: [(Puzzle, String)], at index: Int) {
        let queue = limited(Array(due[index...]) + Array(due[..<index]))
        session = PuzzleSessionSetup(kind: .review, title: "From your games", puzzles: queue.map(\.0),
                                     sources: Dictionary(queue.map { ($0.0.id, $0.1) }, uniquingKeysWith: { a, _ in a }))
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

    /// Level as a big mono number with Icons8 − / +, theme chips, one primary button.
    @ViewBuilder
    private var practice: some View {
        ScreenSectionTitle("Practice")
            .padding(.top, 30)
            .padding(.bottom, DS.Spacing.sm)
        HStack(alignment: .center, spacing: DS.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: String(rating))
                    .font(.system(size: 44, weight: .heavy))
                    .tracking(-1.5)
                    .monospacedDigit()
                    .foregroundStyle(DS.Color.text)
                    .contentTransition(.numericText(value: Double(rating)))
                Text(available == 1 ? "1 puzzle left at this level" : "\(available) puzzles left at this level")
                    .font(DS.Font.subheadline.monospacedDigit())
                    .foregroundStyle(DS.Color.textSecondary)
            }
            Spacer()
            stepButton("minus", label: "Easier", enabled: rating > PuzzleBank.ratingRange.lowerBound) { rating -= 100 }
            stepButton("plus", label: "Harder", enabled: rating < PuzzleBank.ratingRange.upperBound - 100) { rating += 100 }
        }
        .accessibilityElement(children: .contain)
        FlowLayout {
            Chip(title: "Mixed", selected: theme.isEmpty) { theme = "" }
            ForEach(PuzzleBank.practiceThemes, id: \.self) { key in
                Chip(title: PuzzleBank.title(forTheme: key), selected: theme == key) { theme = key }
            }
        }
        .padding(.top, DS.Spacing.m)
        if remainingToday == 0 {
            FreeLimitNote()
                .padding(.top, DS.Spacing.l)
        } else {
            PrimaryButton(title: "Start practice", action: startPractice)
                .padding(.top, DS.Spacing.l)
            if let left = remainingToday {
                Text(left == 1 ? "1 free puzzle left today" : "\(left) free puzzles left today")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Spacing.xs)
            }
        }
    }

    private func stepButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            IconImage(icon, size: 18)
                .foregroundStyle(DS.Color.text)
                .frame(width: 44, height: 44)
                .background(DS.Color.surface2, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
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
        session = PuzzleSessionSetup(kind: .practice, title: title, puzzles: limited(pool), theme: chosen)
    }
}

/// Replaces Start practice once the free puzzles for today are used (flat, no card).
private struct FreeLimitNote: View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
