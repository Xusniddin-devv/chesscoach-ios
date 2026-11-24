import Foundation
import ChessCore

/// Everything the Profile tab shows, computed from the saved games. Unreadable records are
/// skipped (they stay in the store; `GameRecord.snapshot` logs them), and so are analysis-board
/// games (`GameSnapshot.isFreeplay`). Unfinished games
/// (abandoned before a result) appear in the filmstrip but not in the rating.
struct ProfileModel {
    struct Game: Identifiable {
        let record: GameRecord
        let snapshot: GameSnapshot
        /// The user's accuracy: from the full analysis when there is one, else from the
        /// grades made while playing (Training).
        let accuracy: Double?

        var id: UUID { record.id }
        var bot: Bot? { snapshot.isImported ? nil : Bot.all.first { $0.id == snapshot.botId } }
        /// The bot, or an imported game's human opponent.
        var botName: String { bot?.name ?? snapshot.opponentName ?? snapshot.botId }
        var outcome: RatedGame.Outcome? { ProfileModel.outcome(of: snapshot) }

        /// The final position.
        var finalFen: String {
            var fen = snapshot.startFen
            for uci in snapshot.moves {
                guard let applied = Rules.apply(uci: uci, to: fen) else { break }
                fen = applied.fenAfter
            }
            return fen
        }
    }

    /// How the user's moves in one game split into good-or-better and the three bad classes.
    struct MoveQuality: Identifiable, Equatable {
        let id: UUID
        var good = 0
        var inaccuracies = 0
        var mistakes = 0
        var blunders = 0

        var total: Int { good + inaccuracies + mistakes + blunders }
    }

    /// One habit, with how many games it showed up in and the latest move that shows it.
    struct Weakness: Identifiable {
        let summary: WeaknessSummary
        let games: Int
        let example: Example?

        var id: Motif { summary.motif }
        var motif: Motif { summary.motif }

        struct Example {
            let verdict: Verdict
            let botName: String
            /// The bot's next move went to the square the piece was left on.
            let opponentTookIt: Bool
            let userColor: Piece.Color

            var square: Square { Square(String(verdict.uci.dropFirst(2).prefix(2))) }
        }
    }

    /// Readable games against the bots, newest first. Analysis-board games (`isFreeplay`)
    /// have no opponent and are never part of the rating or the stats.
    let games: [Game]
    let ratedGames: [RatedGame]
    let estimate: Int?

    static let gamesForRating = 3
    /// Games in the "How you move" window (and the one before it, for the delta).
    static let window = 10

    init(records: [GameRecord]) {
        games = records
            .compactMap { record in record.snapshot.map { (record, $0) } }
            .filter { !$0.1.isFreeplay }
            .sorted { $0.1.date > $1.1.date }
            .map { Game(record: $0.0, snapshot: $0.1, accuracy: Self.accuracy(of: $0.1)) }
        ratedGames = games.compactMap { game in
            guard let outcome = game.outcome else { return nil }
            // Imported games carry the human opponent's rating.
            let elo = game.bot?.elo ?? game.snapshot.opponentRating ?? PlayerProfile.defaultRating
            return RatedGame(botElo: elo, outcome: outcome, accuracy: game.accuracy)
        }
        estimate = estimateRating(ratedGames)
    }

    // MARK: Rating

    /// Training thresholds and explanation wording: the estimate once there is one.
    var trainingRating: Int { estimate ?? PlayerProfile.defaultRating }

    /// The player's piece; a Pawn until there is a rating.
    var tier: RatingTier { estimate.map(RatingTier.init(rating:)) ?? .pawn }

    var finishedCount: Int { ratedGames.count }

    /// Finished games still needed for a rating.
    var gamesUntilRating: Int { max(0, Self.gamesForRating - ratedGames.count) }

    /// Share of finished games won, 0…1; nil with none.
    var winRate: Double? {
        guard !ratedGames.isEmpty else { return nil }
        return Double(ratedGames.filter { $0.outcome == .win }.count) / Double(ratedGames.count)
    }

    // MARK: How you move

    /// Accuracies of the games that have one, newest first.
    private var accuracies: [Double] { games.compactMap(\.accuracy) }

    /// Average accuracy over the last `window` games with one, and how many games that is.
    var recentAccuracy: (value: Double, games: Int)? {
        let recent = accuracies.prefix(Self.window)
        guard !recent.isEmpty else { return nil }
        return (recent.reduce(0, +) / Double(recent.count), recent.count)
    }

    /// Change against the `window` games before those; nil without earlier games.
    var accuracyDelta: Double? {
        let earlier = accuracies.dropFirst(Self.window).prefix(Self.window)
        guard let recent = recentAccuracy, !earlier.isEmpty else { return nil }
        return recent.value - earlier.reduce(0, +) / Double(earlier.count)
    }

    /// One column per recent game with graded user moves, oldest first.
    var moveQuality: [MoveQuality] {
        games.prefix(Self.window).reversed().compactMap { game in
            var quality = MoveQuality(id: game.id)
            for verdict in Self.userVerdicts(game.snapshot) {
                switch verdict.classification {
                case .inaccuracy: quality.inaccuracies += 1
                case .mistake, .miss: quality.mistakes += 1
                case .blunder: quality.blunders += 1
                default: quality.good += 1
                }
            }
            return quality.total > 0 ? quality : nil
        }
    }

    // MARK: What keeps costing you

    /// Motifs of the user's negative moves across all games, most frequent first.
    var weaknesses: [Weakness] {
        let negative = games.map { game in
            (game: game, verdicts: Self.userVerdicts(game.snapshot).filter { $0.classification.isNegative })
        }
        let summaries = aggregateWeaknesses(negative.flatMap { entry in
            entry.verdicts.map { (motifs: $0.motifs, date: entry.game.snapshot.date) }
        })
        return summaries.map { summary in
            let withMotif = negative.filter { entry in entry.verdicts.contains { $0.motifs.contains(summary.motif) } }
            let example = withMotif.first.flatMap { entry -> Weakness.Example? in
                guard let verdict = entry.verdicts.first(where: { $0.motifs.contains(summary.motif) }) else { return nil }
                let moves = entry.game.snapshot.moves
                let target = verdict.uci.dropFirst(2).prefix(2)
                let reply = verdict.ply < moves.count ? moves[verdict.ply] : nil
                return Weakness.Example(
                    verdict: verdict, botName: entry.game.botName,
                    opponentTookIt: reply.map { $0.dropFirst(2).prefix(2) == target } ?? false,
                    userColor: entry.game.snapshot.userColor)
            }
            return Weakness(summary: summary, games: withMotif.count, example: example)
        }
    }

    /// Games that count towards a weakness' frequency (those with graded user moves).
    var gradedGames: Int { games.filter { !Self.userVerdicts($0.snapshot).isEmpty }.count }

    // MARK: Per game

    static func outcome(of snapshot: GameSnapshot) -> RatedGame.Outcome? {
        switch snapshot.result {
        case .ongoing: nil
        case .draw: .draw
        case .whiteWins: snapshot.userColor == .white ? .win : .loss
        case .blackWins: snapshot.userColor == .black ? .win : .loss
        }
    }

    /// The analysis' grades of the user's moves when the game was analysed, else the live ones.
    static func userVerdicts(_ snapshot: GameSnapshot) -> [Verdict] {
        let all = snapshot.analysis?.verdicts ?? snapshot.verdicts
        return all.filter { $0.mover == snapshot.userColor }
    }

    static func accuracy(of snapshot: GameSnapshot) -> Double? {
        if let analysis = snapshot.analysis {
            guard analysis.verdicts.contains(where: { $0.mover == snapshot.userColor }) else { return nil }
            return snapshot.userColor == .white ? analysis.accuracyWhite : analysis.accuracyBlack
        }
        return userAccuracy(verdicts: snapshot.verdicts, userColor: snapshot.userColor)
    }

    /// "Like Bc4 here — Pip took it for free."
    static func context(for weakness: Weakness) -> String? {
        guard let example = weakness.example else { return nil }
        let san = example.verdict.san
        let bot = example.botName
        let best = example.verdict.bestSan
        switch weakness.motif {
        case .hangingPiece:
            return "Like \(san) here — \(bot) \(example.opponentTookIt ? "took it" : "could take it") for free."
        case .allowedFork: return "Like \(san) here — it let \(bot) attack two pieces at once."
        case .allowedMate: return "Like \(san) here — it let \(bot) force checkmate."
        case .missedMate: return "Like \(san) here — \(best) was checkmate in a few moves."
        case .missedCapture: return "Like \(san) here — \(best) won material instead."
        case .openingPrinciple: return "Like \(san) here — before the knights and bishops were out."
        }
    }
}
