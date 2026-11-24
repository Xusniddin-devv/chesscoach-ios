import SwiftUI
import SwiftData
import ChessCore

/// The Profile tab ("You"): your piece (rating tier) with the way to the next one, your last
/// games as a filmstrip of final positions (→ Review), how you move (accuracy and the quality
/// of your moves per game), and what keeps costing you (habits, shown on a real position).
struct ProfileView: View {
    private enum Route: Hashable { case review(GameRecord), settings }

    @Query(sort: \GameRecord.date, order: .reverse) private var records: [GameRecord]
    @Query(sort: \UserProfile.updated, order: .reverse) private var profiles: [UserProfile]
    @Query private var progress: [PuzzleProgress]
    @Environment(Entitlements.self) private var entitlements
    @State private var path: [Route] = []
    @State private var scroll = ScrollPosition(edge: .top)
    @State private var fixSession: PuzzleSessionSetup?
    @State private var paywall = false

    /// Puzzles in a "Fix it" session.
    static let fixCount = 5

    static let margin: CGFloat = 20

    var body: some View {
        let model = ProfileModel(records: records)
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PieceHero(model: model, goal: goal(model))
                    lastGames(model)
                    if let accuracy = model.recentAccuracy {
                        howYouMove(model, accuracy: accuracy)
                    }
                    let weaknesses = model.weaknesses
                    if !weaknesses.isEmpty {
                        costing(Array(weaknesses.prefix(3)), model: model)
                    }
                    #if DEBUG
                    NavigationLink("Engine benchmark (debug)") { EngineBenchmarkView() }
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .padding(.top, DS.Spacing.xl)
                    #endif
                }
                .padding(.horizontal, Self.margin)
                .padding(.bottom, DS.Spacing.xl)
            }
            // Clear the floating tab bar: the last section never ends under it.
            .contentMargins(.bottom, DS.Spacing.l, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollPosition($scroll)
            .background(DS.Color.background)
            .navigationTitle("You")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Route.settings) {
                        Image("Icons/settings").renderingMode(.template)
                            .foregroundStyle(DS.Color.text)  // a quiet control, not an accent key
                    }
                    .accessibilityLabel("Settings")
                }
            }
            #if DEBUG
            .task {
                guard UserDefaults.standard.string(forKey: "debugScroll") == "bottom" else { return }
                try? await Task.sleep(for: .seconds(1))
                scroll.scrollTo(edge: .bottom)
            }
            #endif
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .review(let record): ReviewView(record: record)
                case .settings: SettingsView()
                }
            }
        }
        .fullScreenCover(item: $fixSession) { PuzzleSessionView(setup: $0) }
        .paywall(isPresented: $paywall, feature: .unlimitedPuzzles)
        #if DEBUG
        .task { if ["settings", "paywall", "licenses"].contains(UserDefaults.standard.string(forKey: "debugOpen")) { path = [.settings] } }
        .task {
            // `-debugFix 1`: "Fix it" for the top habit (screenshots).
            guard UserDefaults.standard.string(forKey: "debugFix") != nil,
                  let top = ProfileModel(records: records).weaknesses.first else { return }
            fix(top.motif, model: ProfileModel(records: records))
        }
        #endif
    }

    // MARK: Goal and Fix it

    /// The saved goal from onboarding, measured from the current estimate (else the
    /// platform rating): "Goal 1200 by March · 260 to go". Nil without a goal.
    private func goal(_ model: ProfileModel) -> PieceHero.Goal? {
        guard let profile = profiles.first, let target = profile.goalRating else { return nil }
        return PieceHero.Goal(target: target, by: profile.goalDate,
                              current: model.estimate ?? profile.currentRating)
    }

    /// Five puzzles for one habit: the user's own positions first, then bank puzzles on its
    /// themes. Uses the free daily allowance like the Puzzles tab.
    private func fix(_ motif: Motif, model: ProfileModel) {
        let remaining = PuzzleAllowance.remaining(progress, dailyId: PuzzleBank.daily(for: .now)?.id,
                                                  isPro: entitlements.isPro)
        if remaining == 0 { paywall = true; return }
        let snapshots = records.compactMap(\.snapshot)
        let puzzles = BlunderPuzzles.fixIt(motif, snapshots: snapshots, rating: model.trainingRating,
                                           count: min(Self.fixCount, remaining ?? Self.fixCount))
        guard !puzzles.isEmpty else { return }
        let own = Set(snapshots.filter { !$0.isFreeplay }.flatMap { BlunderPuzzles.from(snapshot: $0) }.map(\.id))
        fixSession = PuzzleSessionSetup(
            kind: .review, title: motif.title, puzzles: puzzles,
            sources: Dictionary(puzzles.map { ($0.id, own.contains($0.id) ? "blunder" : "bank") }, uniquingKeysWith: { a, _ in a }),
            theme: PuzzleBank.themes(for: motif).first)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold))
            .tracking(-0.3)
            .foregroundStyle(DS.Color.text)
            .padding(.top, 30)
            .padding(.bottom, DS.Spacing.sm)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Your last games

    @ViewBuilder
    private func lastGames(_ model: ProfileModel) -> some View {
        sectionTitle("Your last games")
        if model.games.isEmpty {
            Text("Play a bot and your games show up here.")
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(model.games.prefix(20)) { game in
                        NavigationLink(value: Route.review(game.record)) {
                            GameThumb(game: game)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Self.margin)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Self.margin)
        }
    }

    // MARK: How you move

    @ViewBuilder
    private func howYouMove(_ model: ProfileModel, accuracy: (value: Double, games: Int)) -> some View {
        sectionTitle("How you move")
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(Int(accuracy.value.rounded()))")
                .font(.system(size: 44, weight: .heavy))
                .tracking(-1.5)
                .foregroundStyle(DS.Color.text)
            Text("accuracy, last \(accuracy.games) \(accuracy.games == 1 ? "game" : "games")")
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
            if let delta = model.accuracyDelta, Int(delta.rounded()) != 0 {
                let points = Int(delta.rounded())
                Text("\(points > 0 ? "↑" : "↓") \(abs(points))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(points > 0 ? DS.Color.accent : DS.Color.textSecondary)
                    .accessibilityLabel("\(points > 0 ? "up" : "down") \(abs(points)) on the games before")
            }
        }
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
        let columns = model.moveQuality
        if !columns.isEmpty {
            MoveQualityRibbon(columns: columns)
        }
    }

    // MARK: What keeps costing you

    @ViewBuilder
    private func costing(_ weaknesses: [ProfileModel.Weakness], model: ProfileModel) -> some View {
        let gradedGames = model.gradedGames
        sectionTitle("What keeps costing you")
        if let top = weaknesses.first {
            WeaknessCard(weakness: top, gradedGames: gradedGames, fixCount: Self.fixCount) { fix(top.motif, model: model) }
        }
        VStack(spacing: 0) {
            ForEach(weaknesses.dropFirst()) { weakness in
                HStack {
                    Text(weakness.motif.title)
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Color.text)
                    Spacer()
                    FrequencyPips(on: weakness.games, of: gradedGames, maxPips: 5)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 2)
                .overlay(alignment: .bottom) { Rectangle().fill(DS.Color.surface2).frame(height: 1) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(weakness.motif.title), in \(weakness.games) of \(gradedGames) games")
            }
        }
        .padding(.top, DS.Spacing.xs)
    }
}

// MARK: Hero

/// "Your piece": the rating in heavy numerals, the tier's name, the tier's cream piece large
/// on the right, and the way to the next tier as eight board squares.
private struct PieceHero: View {
    struct Goal {
        let target: Int
        let by: Date?
        let current: Int
    }

    let model: ProfileModel
    let goal: Goal?

    var body: some View {
        let tier = model.tier
        ZStack(alignment: .topLeading) {
            Image(PieceImage.assetName(Piece(tier.pieceKind, color: .white, square: .a1)))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 250, height: 250)
                .shadow(color: .black.opacity(0.55), radius: 20, y: 30)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: 56, y: -6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Your piece")
                    .font(DS.Font.subheadline)
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(.top, DS.Spacing.s)
                if let estimate = model.estimate {
                    Text(estimate, format: .number.grouping(.never))
                        .font(.system(size: 96, weight: .heavy))
                        .tracking(-4)
                        .foregroundStyle(DS.Color.text)
                        .padding(.top, -6)
                        .padding(.bottom, -14)  // the numerals' line box is taller than the digits
                        .accessibilityLabel("Rating \(estimate)")
                    Text(tier.name)
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(DS.Color.text)
                    if let goal { GoalLine(goal: goal).padding(.top, 4) }
                    if let next = tier.next, let points = tier.pointsToNext(from: estimate) {
                        TierTrack(filled: Int((tier.progress(of: estimate) * 8).rounded(.down)), next: next)
                            .padding(.top, 22)
                        Text("\(points) points to \(next.name)")
                            .font(.system(size: 13))
                            .foregroundStyle(DS.Color.textSecondary)
                            .padding(.top, DS.Spacing.s)
                    } else {
                        Text("The top piece")
                            .font(.system(size: 13))
                            .foregroundStyle(DS.Color.textSecondary)
                            .padding(.top, 22)
                    }
                } else {
                    Text(tier.name)
                        .font(.system(size: 64, weight: .heavy))
                        .tracking(-2)
                        .foregroundStyle(DS.Color.text)
                        .padding(.top, DS.Spacing.xs)
                    TierTrack(filled: model.finishedCount, cells: ProfileModel.gamesForRating, next: nil)
                        .padding(.top, 22)
                    Text("Play \(ProfileModel.gamesForRating) games to find your piece")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Color.textSecondary)
                        .padding(.top, DS.Spacing.s)
                    Text("\(model.finishedCount) of \(ProfileModel.gamesForRating) played")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(DS.Color.textSecondary)
                        .padding(.top, 2)
                }
            }
        }
        .frame(height: 250, alignment: .top)
        .accessibilityElement(children: .combine)
    }
}

/// "Goal 1200 by March · 260 to go" (onboarding's goal); "reached" once the estimate is there.
private struct GoalLine: View {
    let goal: PieceHero.Goal

    var body: some View {
        let toGo = goal.target - goal.current
        HStack(spacing: 0) {
            Text("Goal ")
            Text(verbatim: String(goal.target)).monospacedDigit().fontWeight(.semibold).foregroundStyle(DS.Color.text)
            if let by = goal.by { Text(" by \(by.formatted(.dateTime.month(.wide)))") }
            Text(toGo > 0 ? " · \(toGo) to go" : " · reached")
        }
        .font(.system(size: 13))
        .foregroundStyle(DS.Color.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
}

/// Progress as board squares: filled cells alternate board light and dark, empty ones are
/// `surface2`; the next tier's piece waits at the end.
private struct TierTrack: View {
    let filled: Int
    var cells = 8
    let next: RatingTier?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<cells, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < filled ? (index.isMultiple(of: 2) ? DS.Color.boardLight : DS.Color.boardDark)
                                         : DS.Color.surface2)
                    .frame(height: 10)
            }
            if let next {
                Image(PieceImage.assetName(Piece(next.pieceKind, color: .white, square: .a1)))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 26, height: 26)
                    .opacity(0.45)
                    .padding(.leading, 6)
            }
        }
        .frame(width: cells == 8 ? 212 : 96, alignment: .leading)
        .accessibilityHidden(true)
    }
}

// MARK: Filmstrip

/// One saved game: its final position, the result on the board's corner, and the bot and
/// your accuracy under it.
private struct GameThumb: View {
    let game: ProfileModel.Game

    static let side: CGFloat = 112

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            MiniBoardView(fen: game.finalFen, orientation: game.snapshot.userColor)
                .frame(width: Self.side, height: Self.side)
                .overlay(alignment: .topLeading) { resultTag.padding(6) }
            HStack(spacing: 6) {
                if let bot = game.bot {
                    Image(bot.avatarAsset)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .background(DS.Color.boardDark, in: RoundedRectangle(cornerRadius: 5))
                }
                Text(game.botName)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Color.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let accuracy = game.accuracy {
                    Text("\(Int(accuracy.rounded()))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            .frame(width: Self.side)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(result.text) against \(game.botName)"
                            + (game.accuracy.map { ", accuracy \(Int($0.rounded())) percent" } ?? ""))
        .accessibilityAddTraits(.isButton)
    }

    private var result: (text: String, accent: Bool) {
        switch game.outcome {
        case .win: ("Won", true)
        case .loss: ("Lost", false)
        case .draw: ("Drawn", false)
        case nil: ("Unfinished", false)
        }
    }

    private var resultTag: some View {
        Text(result.text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(result.accent ? DS.Color.accent : DS.Color.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(DS.Color.background, in: RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: Move quality

/// One stacked column per game, good-or-better at the bottom, then inaccuracies, mistakes
/// and blunders, in the move-class colours; a small legend under it.
private struct MoveQualityRibbon: View {
    let columns: [ProfileModel.MoveQuality]

    private struct Segment {
        let name: String
        let color: Color
        let count: (ProfileModel.MoveQuality) -> Int
    }

    /// Capped so the ribbon reads as a strip of games, not tall slabs.
    static let height: CGFloat = 96
    static let columnWidth: CGFloat = 26

    /// Top to bottom. Flat class colours, no gradient.
    private static let segments = [
        Segment(name: "Blunder", color: DS.Color.moveClass(.blunder), count: \.blunders),
        Segment(name: "Mistake", color: DS.Color.moveClass(.mistake), count: \.mistakes),
        Segment(name: "Inaccuracy", color: DS.Color.moveClass(.inaccuracy), count: \.inaccuracies),
        Segment(name: "Good+", color: DS.Color.moveClass(.best), count: \.good),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(columns) { column in
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            ForEach(Self.segments, id: \.name) { segment in
                                let count = segment.count(column)
                                if count > 0 {
                                    segment.color
                                        .frame(height: geo.size.height * CGFloat(count) / CGFloat(column.total))
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .frame(width: Self.columnWidth)
                    .accessibilityElement()
                    .accessibilityLabel("\(column.good) good, \(column.inaccuracies) inaccuracies, \(column.mistakes) mistakes, \(column.blunders) blunders")
                }
            }
            .frame(height: Self.height, alignment: .bottomLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 14) {
                ForEach(Self.segments.reversed(), id: \.name) { segment in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(segment.color).frame(width: 8, height: 8)
                        Text(segment.name)
                    }
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(DS.Color.textSecondary)
            .accessibilityHidden(true)
        }
    }
}

// MARK: Weakness

/// The habit that costs the most, on the real position where it last happened.
private struct WeaknessCard: View {
    let weakness: ProfileModel.Weakness
    let gradedGames: Int
    let fixCount: Int
    let onFix: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let example = weakness.example {
                MiniBoardView(fen: example.verdict.facts.fenAfter, highlight: example.square,
                              badge: example.verdict.classification, orientation: example.userColor)
                    .frame(width: 118, height: 118)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(weakness.motif.headline)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Color.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let context = ProfileModel.context(for: weakness) {
                    Text(context)
                        .font(.system(size: 14))
                        .foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                FrequencyPips(on: weakness.games, of: gradedGames, maxPips: 7)
                    .padding(.top, 2)
                Button(action: onFix) {
                    Text("Fix it · \(fixCount) puzzles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Color.onAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(DS.Color.accent, in: RoundedRectangle(cornerRadius: 11))
                        .background(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 11).fill(DS.Color.accentPressed).offset(y: 3)
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

/// How often a habit showed up: red pips for the games with it, out of the graded games
/// (scaled down to `maxPips` when there are more games).
private struct FrequencyPips: View {
    let on: Int
    let of: Int
    let maxPips: Int

    var body: some View {
        let total = min(max(of, 1), maxPips)
        let lit = of <= maxPips ? on : max(1, Int((Double(on) / Double(of) * Double(maxPips)).rounded()))
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < lit ? DS.Color.danger : DS.Color.surface2)
                    .frame(width: 16, height: 5)
            }
        }
        .accessibilityHidden(true)
    }
}
