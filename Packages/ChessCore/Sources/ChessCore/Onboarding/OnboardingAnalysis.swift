import Foundation

/// What the onboarding import screen hears while games are analysed one after another.
public enum OnboardingEvent: Sendable, Equatable {
    /// Game `index` (0-based) of `total` started.
    case gameStarted(index: Int, total: Int)
    /// Position `done` of `positions` in game `index` was searched.
    case position(index: Int, done: Int, positions: Int)
    /// Game `index` finished; the snapshot now carries its analysis.
    case gameFinished(index: Int, snapshot: GameSnapshot)
    /// Game `index` could not be analysed (illegal move, engine error); it is kept unanalysed.
    case gameFailed(index: Int)
}

/// Runs `GameAnalyzer` over imported games one at a time (one engine), reporting each step.
/// Depth 12: onboarding wants an answer in minutes, not the review-grade depth.
public struct OnboardingAnalysis: Sendable {
    public static let defaultDepth = 12

    public let engine: any ChessEngine
    public let depth: Int

    public init(engine: any ChessEngine, depth: Int = OnboardingAnalysis.defaultDepth) {
        self.engine = engine
        self.depth = depth
    }

    /// Returns every game, analysed where possible, in the input order. Cancelling stops after
    /// the current position and returns what is done (finished games analysed, the rest not).
    public func run(_ games: [GameSnapshot],
                    onEvent: @Sendable (OnboardingEvent) -> Void) async -> [GameSnapshot] {
        var out = games
        let analyzer = GameAnalyzer(engine: engine, depth: depth)
        for (i, game) in games.enumerated() {
            if Task.isCancelled { break }
            onEvent(.gameStarted(index: i, total: games.count))
            do {
                let analysis = try await analyzer.analyze(startFen: game.startFen, moves: game.moves) { done, total in
                    onEvent(.position(index: i, done: done, positions: total))
                }
                var analysed = game
                analysed.analysis = analysis
                out[i] = analysed
                onEvent(.gameFinished(index: i, snapshot: analysed))
            } catch is CancellationError {
                break
            } catch {
                onEvent(.gameFailed(index: i))
            }
        }
        return out
    }
}

/// The user's side of one analysed game.
public struct GameSummary: Sendable, Equatable {
    public var accuracy: Double?
    public var won: Bool?
    /// Worst user move (largest win drop among mistakes/blunders/misses), if any.
    public var worst: Verdict?
    public var counts: [MoveClass: Int]

    public init(_ snapshot: GameSnapshot) {
        let verdicts = (snapshot.analysis?.verdicts ?? snapshot.verdicts).filter { $0.mover == snapshot.userColor }
        accuracy = snapshot.analysis.map { snapshot.userColor == .white ? $0.accuracyWhite : $0.accuracyBlack }
        switch snapshot.result {
        case .whiteWins: won = snapshot.userColor == .white
        case .blackWins: won = snapshot.userColor == .black
        case .draw, .ongoing: won = nil
        }
        worst = verdicts.filter { BlunderPuzzles.classes.contains($0.classification) }.max { $0.winDrop < $1.winDrop }
        counts = Dictionary(verdicts.map { ($0.classification, 1) }, uniquingKeysWith: +)
    }
}

/// What a set of analysed games says about the player.
public struct WeaknessReport: Sendable, Equatable {
    public struct Weakness: Sendable, Equatable {
        public var motif: Motif
        /// Times it happened in the user's moves.
        public var count: Int
        /// Games it happened in.
        public var games: Int
        /// The costliest example: the game and the verdict.
        public var exampleGameId: UUID?
        public var example: Verdict?
    }

    public var gamesAnalysed: Int
    public var averageAccuracy: Double?
    /// Most frequent first; ties by games affected, then by the motif's fixed order.
    public var weaknesses: [Weakness]
    public var blunders: Int
    public var mistakes: Int

    public var top: [Motif] { weaknesses.map(\.motif) }

    public init(_ games: [GameSnapshot]) {
        let analysed = games.filter { $0.analysis != nil }
        gamesAnalysed = analysed.count
        let accuracies = analysed.compactMap { GameSummary($0).accuracy }
        averageAccuracy = accuracies.isEmpty ? nil : accuracies.reduce(0, +) / Double(accuracies.count)

        var byMotif: [Motif: Weakness] = [:]
        var blunders = 0, mistakes = 0
        for game in analysed {
            var seen: Set<Motif> = []
            for v in game.analysis?.verdicts ?? [] where v.mover == game.userColor {
                if v.classification == .blunder { blunders += 1 }
                if v.classification == .mistake || v.classification == .miss { mistakes += 1 }
                guard BlunderPuzzles.classes.contains(v.classification) else { continue }
                for motif in v.motifs {
                    var w = byMotif[motif] ?? Weakness(motif: motif, count: 0, games: 0)
                    w.count += 1
                    if !seen.contains(motif) { w.games += 1; seen.insert(motif) }
                    if (w.example?.winDrop ?? -1) < v.winDrop { w.example = v; w.exampleGameId = game.id }
                    byMotif[motif] = w
                }
            }
        }
        self.blunders = blunders
        self.mistakes = mistakes
        let order = Motif.allCases
        weaknesses = byMotif.values.sorted {
            ($0.count, $0.games, -(order.firstIndex(of: $0.motif) ?? 0))
                > ($1.count, $1.games, -(order.firstIndex(of: $1.motif) ?? 0))
        }
    }
}

extension Motif: CaseIterable {
    public static let allCases: [Motif] = [
        .hangingPiece, .allowedFork, .missedCapture, .allowedMate, .missedMate, .openingPrinciple,
    ]

    /// How the coach names the habit, as a sentence subject: "You leave pieces undefended".
    public var habit: String {
        switch self {
        case .hangingPiece: "You leave pieces undefended"
        case .allowedFork: "You walk into forks"
        case .missedCapture: "You miss free material"
        case .allowedMate: "You let mates through"
        case .missedMate: "You miss checkmates"
        case .openingPrinciple: "Your queen comes out too early"
        }
    }

    /// Short name for plan days and chips: "Undefended pieces".
    public var shortName: String {
        switch self {
        case .hangingPiece: "Undefended pieces"
        case .allowedFork: "Forks"
        case .missedCapture: "Free material"
        case .allowedMate: "Mate threats"
        case .missedMate: "Finding mate"
        case .openingPrinciple: "Opening basics"
        }
    }
}
