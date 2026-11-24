import SwiftUI
import SwiftData
import ChessCore

/// Puzzles tab in the coach's voice: the coach with the streak and today's hook, the daily
/// puzzle as the hero, own mistakes as a filmstrip, and practice — the level on a scrubbable
/// rating ruler (the onboarding goal picker's bars) and the themes as rows of chunky piece
/// tokens with solved ticks. No pills, no stepper, no card grid.
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
    @State private var scroll = ScrollPosition(edge: .top)

    private static let sessionLength = 10
    static let margin: CGFloat = 20

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    coach
                    daily
                    mistakes
                    practice
                }
                .padding(.horizontal, Self.margin)
                .padding(.bottom, DS.Spacing.xl)
            }
            // Clear the floating tab bar.
            .contentMargins(.bottom, 96, for: .scrollContent)
            .scrollPosition($scroll)
            .scrollIndicators(.hidden)
            .background(DS.Color.background)
            .navigationTitle("Puzzles")
        }
        .fullScreenCover(item: $session) { PuzzleSessionView(setup: $0) }
        .task(id: GameRecord.fingerprint(games)) { blunders = Self.blunderPuzzles(from: games) }
        #if DEBUG
        .task {
            guard let target = UserDefaults.standard.string(forKey: "debugScroll") else { return }
            try? await Task.sleep(for: .seconds(1))
            if target == "practice" { scroll.scrollTo(y: 560) } else { scroll.scrollTo(edge: .bottom) }
        }
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
        // Memoised per record; sync copies of a game count once.
        GameRecord.unique(games).filter { $0.snapshot?.isFreeplay == false }.flatMap(\.blunderPuzzles)
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

    // MARK: Coach

    /// The coach carries the streak and today's hook ("Day 3 of your streak. Today's puzzle
    /// is a knight fork."), from the real streak and the daily puzzle's solution.
    private var coach: some View {
        HStack(alignment: .bottom, spacing: 0) {
            CoachAvatar(pose: dailyDone ? .pleased : .neutral, size: 92)
                .padding(.leading, -12)
            CoachText(coachLine)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DS.Color.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.Spacing.m)
                .padding(.vertical, DS.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BubbleShape(tailY: 20).fill(DS.Color.surface))
                .padding(.bottom, 18)
        }
        .padding(.top, DS.Spacing.xs)
        .padding(.bottom, DS.Spacing.m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach: \(CoachText.plain(coachLine))")
    }

    private var dailyDone: Bool {
        guard let id = PuzzleBank.daily(for: .now)?.id else { return false }
        return progressById[id]?.lastSolved.map { Calendar.current.isDateInToday($0) } ?? false
    }

    private var coachLine: String {
        let days = streak.current(now: .now)
        let lead = days > 0 ? "**Day \(days)** of your streak." : "No streak yet. One puzzle starts it."
        guard let puzzle = PuzzleBank.daily(for: .now) else { return lead }
        if dailyDone { return lead + " Today's puzzle is done. Practice keeps the board warm." }
        return lead + " Today's puzzle is **\(Self.hook(for: puzzle))**."
    }

    /// "a knight fork", "mate in two", "a bishop pin": the solution's piece and theme.
    static func hook(for puzzle: Puzzle) -> String {
        let theme = PuzzleBank.practiceThemes.first { puzzle.themes.contains($0) }
        var piece = "move"
        if let fen = puzzle.solvingFen, puzzle.moves.indices.contains(puzzle.firstSolverIndex),
           let kind = Rules.piece(at: Square(String(puzzle.moves[puzzle.firstSolverIndex].prefix(2))), fen: fen)?.kind {
            piece = LessonQuestion.glyph(kind)
        }
        switch theme {
        case "mateIn1": return "mate in one"
        case "mateIn2": return "mate in two"
        case "mateIn3": return "mate in three"
        case "backRankMate": return "a back-rank mate"
        case "fork": return "a \(piece) fork"
        case "pin": return "a \(piece) pin"
        case "skewer": return "a \(piece) skewer"
        case "hangingPiece": return "a free piece to take"
        case "discoveredAttack": return "a discovered attack"
        case "endgame": return "an endgame win"
        default: return "a \(piece) move to find"
        }
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

    /// The level on a ruler, then one row per theme: tap a row to start ten puzzles there.
    @ViewBuilder
    private var practice: some View {
        ScreenSectionTitle("Practice")
            .padding(.top, 30)
            .padding(.bottom, DS.Spacing.xs)
            .id("practice")
        Text("Around **\(rating)** · \(available) you haven't seen")
            .font(DS.Font.subheadline.monospacedDigit())
            .foregroundStyle(DS.Color.textSecondary)
            .contentTransition(.numericText(value: Double(rating)))
        RatingRuler(value: $rating, range: PuzzleBank.ratingRange.lowerBound...(PuzzleBank.ratingRange.upperBound - 100))
            .padding(.top, DS.Spacing.s)
        if remainingToday == 0 {
            FreeLimitNote()
                .padding(.vertical, DS.Spacing.l)
        } else if let left = remainingToday {
            Text(left == 1 ? "1 free puzzle left today" : "\(left) free puzzles left today")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.top, DS.Spacing.s)
        }
        VStack(spacing: 0) {
            ThemeRow(glyph: "tab-puzzle", title: "Mixed", detail: "Every theme at your level", solved: solvedCount(nil)) {
                startPractice(nil)
            }
            ForEach(PuzzleBank.practiceThemes, id: \.self) { key in
                ThemeRow(glyph: Self.glyph(forTheme: key), title: PuzzleBank.title(forTheme: key),
                         detail: Self.blurb(forTheme: key), solved: solvedCount(key)) {
                    startPractice(key)
                }
            }
        }
        .padding(.top, DS.Spacing.sm)
    }

    /// Bank puzzles solved, overall or in one theme.
    private func solvedCount(_ theme: String?) -> Int {
        progress.filter { $0.source == "bank" && $0.lastSolved != nil }
            .compactMap { PuzzleBank.puzzle(id: $0.puzzleId) }
            .filter { theme == nil || $0.themes.contains(theme!) }
            .count
    }

    static func glyph(forTheme theme: String) -> String {
        switch theme {
        case "mateIn1", "mateIn2", "mateIn3": "piece-king"
        case "fork": "piece-knight"
        case "pin": "piece-bishop"
        case "skewer", "backRankMate": "piece-rook"
        case "discoveredAttack": "piece-queen"
        case "hangingPiece", "opening": "piece-pawn"
        case "endgame": "piece-king"
        default: "tab-puzzle"
        }
    }

    static func blurb(forTheme theme: String) -> String {
        switch theme {
        case "mateIn1": "Finish the game in one move"
        case "mateIn2": "A check, then mate"
        case "mateIn3": "Three moves to the king"
        case "fork": "One piece, two targets"
        case "pin": "Pinned to a bigger piece"
        case "skewer": "The piece behind falls"
        case "hangingPiece": "Take what nobody guards"
        case "discoveredAttack": "One moves, another attacks"
        case "backRankMate": "King trapped by its own pawns"
        case "endgame": "Few pieces, exact moves"
        case "opening": "Punish early mistakes"
        default: ""
        }
    }

    private var available: Int {
        PuzzleBank.puzzles(band: practiceBand, theme: nil, excluding: attempted).count
    }

    /// The ruler's value is the band's centre: 800 → 700…899.
    private var practiceBand: Range<Int> { PuzzleBank.band(around: rating) }

    private var attempted: Set<String> { Set(progress.map(\.puzzleId)) }

    private func startPractice(_ chosen: String?) {
        if remainingToday == 0 { return }
        theme = chosen ?? ""
        var pool = PuzzleBank.puzzles(band: practiceBand, theme: chosen, excluding: attempted)
        if pool.isEmpty { pool = PuzzleBank.puzzles(band: practiceBand, theme: chosen) }
        guard !pool.isEmpty else { return }
        let title = chosen.map(PuzzleBank.title(forTheme:)) ?? "Practice"
        session = PuzzleSessionSetup(kind: .practice, title: title, puzzles: limited(pool), theme: chosen)
    }
}

/// One practice theme: a chunky round token with the theme's Icons8 piece glyph (the Learn
/// path's tokens), name and one line, and the puzzles solved there as small ticks.
private struct ThemeRow: View {
    let glyph: String
    let title: String
    let detail: String
    let solved: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                IconImage(glyph, size: 24)
                    .foregroundStyle(DS.Color.text)
                    .frame(width: 52, height: 48)
                    .background(DS.Color.surface2, in: Ellipse())
                    .background(alignment: .bottom) {
                        Ellipse().fill(Color(hex: 0x0E1011)).frame(height: 48).offset(y: 4)
                    }
                    .padding(.bottom, 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.Color.text)
                    Text(detail)
                        .font(DS.Font.subheadline)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Spacing.s)
                SolvedTicks(solved: solved)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(solved) solved")
        .accessibilityHint("Starts practice")
    }
}

/// Puzzles solved in a theme as ten small ticks (accent), the count in mono past ten.
private struct SolvedTicks: View {
    let solved: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 2) {
                ForEach(0..<10, id: \.self) { i in
                    Capsule()
                        .fill(i < solved % 10 || (solved >= 10 && solved % 10 == 0) ? DS.Color.accent : DS.Color.surface2)
                        .frame(width: 3, height: 12)
                }
            }
            Text(verbatim: "\(solved)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(DS.Color.textSecondary)
        }
        .accessibilityHidden(true)
    }
}

/// The practice level on a ruler (the onboarding goal picker's language): one bar per
/// 50 points, height from the share of players at that rating, accent up to the chosen
/// level; drag to scrub, a haptic tick every 50, the value on the handle.
struct RatingRuler: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    private var bars: [Int] { Array(stride(from: range.lowerBound, through: range.upperBound, by: 50)) }

    var body: some View {
        let distribution = RatingDistribution.lichess
        let shares = Dictionary(distribution.buckets.map { ($0.rating, $0.share) }, uniquingKeysWith: { a, _ in a })
        let peak = bars.compactMap { shares[$0] }.max() ?? 1
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height - 26
            let pitch = w / CGFloat(bars.count)
            let x = CGFloat(value - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound) * (w - pitch) + pitch / 2
            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(bars, id: \.self) { rating in
                        let share = shares[rating] ?? peak * 0.1
                        Capsule()
                            .fill(rating <= value ? DS.Color.accent : DS.Color.surface2)
                            .frame(width: max(2, pitch * 0.5), height: max(6, h * CGFloat(share / peak) * 0.9 + 6))
                            .frame(width: pitch, height: h, alignment: .bottom)
                    }
                }
                .padding(.top, 26)
                // The handle: the value over a thin line.
                VStack(spacing: 2) {
                    Text(verbatim: String(value))
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundStyle(DS.Color.onAccent)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(DS.Color.accent, in: Capsule())
                    Rectangle().fill(DS.Color.accent).frame(width: 2, height: h)
                }
                .fixedSize()
                .position(x: min(max(x, 28), w - 28), y: (h + 26) / 2 + 1)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let raw = range.lowerBound + Int((drag.location.x - pitch / 2) / (w - pitch) * CGFloat(range.upperBound - range.lowerBound))
                value = min(max((raw + 25) / 50 * 50, range.lowerBound), range.upperBound)
            })
        }
        .frame(height: 104)
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityLabel("Practice level")
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 50, range.upperBound)
            case .decrement: value = max(value - 50, range.lowerBound)
            @unknown default: break
            }
        }
    }
}

/// Replaces the free practice once today's puzzles are used (flat, no card).
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
