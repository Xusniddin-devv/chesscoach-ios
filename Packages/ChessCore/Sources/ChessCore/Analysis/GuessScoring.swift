import Foundation

/// One guess in "Guess the move": what the user played on the board at `ply`, what was played
/// in the game, the engine's best move, and the points the guess earned.
public struct GuessResult: Equatable, Sendable, Identifiable {
    public var ply: Int
    public var guessUci: String
    public var guessSan: String
    /// The guess graded like a played move.
    public var guessClass: MoveClass
    public var cpLoss: Int
    public var playedUci: String
    public var playedSan: String
    public var playedClass: MoveClass
    public var bestUci: String
    public var bestSan: String
    public var points: Int

    public var id: Int { ply }
    public var matchedGame: Bool { guessUci == playedUci }
    public var matchedBest: Bool { guessUci == bestUci }

    public init(ply: Int, guessUci: String, guessSan: String, guessClass: MoveClass, cpLoss: Int,
                playedUci: String, playedSan: String, playedClass: MoveClass,
                bestUci: String, bestSan: String, points: Int) {
        self.ply = ply
        self.guessUci = guessUci
        self.guessSan = guessSan
        self.guessClass = guessClass
        self.cpLoss = cpLoss
        self.playedUci = playedUci
        self.playedSan = playedSan
        self.playedClass = playedClass
        self.bestUci = bestUci
        self.bestSan = bestSan
        self.points = points
    }
}

/// Scoring for "Guess the move": the engine's best move = 3 points, a move within 50 cp of it
/// = 2, within 150 cp = 1, anything else 0.
public enum GuessScoring {
    public static let maxPoints = 3
    public static let closeCp = 50
    public static let nearCp = 150

    public static func points(isBest: Bool, cpLoss: Int) -> Int {
        if isBest { return 3 }
        let loss = max(0, cpLoss)
        if loss <= closeCp { return 2 }
        if loss <= nearCp { return 1 }
        return 0
    }

    /// Grades `guess` at `ply` (1-based) of a game with a saved analysis. The game's own move
    /// and the saved best move need no engine; any other move is searched before and after
    /// (depth `depth`, MultiPV 3) and classified like a played move. Throws engine errors and
    /// `CancellationError`; nil when the ply has no verdict or the guess is illegal.
    public static func grade(guess: String, ply: Int, startFen: String, moves: [String],
                             analysis: GameAnalysis, engine: any ChessEngine,
                             depth: Int = 14) async throws -> GuessResult? {
        guard ply >= 1, ply <= moves.count,
              let saved = analysis.verdicts.first(where: { $0.ply == ply }),
              let fenBefore = Rules.fen(startFen: startFen, moves: Array(moves.prefix(ply - 1))),
              let applied = Rules.apply(uci: guess, to: fenBefore) else { return nil }
        let played = moves[ply - 1]
        let bestUci = saved.bestMove.isEmpty ? played : saved.bestMove
        let bestSan = saved.bestSan.isEmpty ? bestUci : saved.bestSan

        func result(_ moveClass: MoveClass, cpLoss: Int, isBest: Bool) -> GuessResult {
            GuessResult(ply: ply, guessUci: guess, guessSan: applied.san, guessClass: moveClass, cpLoss: cpLoss,
                        playedUci: played, playedSan: saved.san, playedClass: saved.classification,
                        bestUci: bestUci, bestSan: bestSan,
                        points: points(isBest: isBest, cpLoss: cpLoss))
        }

        if guess == played {
            return result(saved.classification, cpLoss: saved.cpLoss, isBest: guess == bestUci)
        }
        if guess == bestUci {
            return result(.best, cpLoss: 0, isBest: true)
        }
        let history = Array(moves.prefix(ply - 1))
        let before = try await engine.analyze(
            AnalysisRequest(startFen: startFen, moves: history, depth: depth, multiPV: 3))
        let after = try await engine.analyze(
            AnalysisRequest(startFen: startFen, moves: history + [guess], depth: depth, multiPV: 3))
        let verdict = classifyPlayed(PlayedMoveInput(
            fenBefore: fenBefore, fenAfter: applied.fenAfter, playedUci: guess, playedSan: applied.san,
            mover: saved.mover, ply: ply, before: before, after: after))
        // A fresh search may prefer the guess over the saved best move: then it is best too.
        let isBest = verdict.bestMove == guess
        return result(verdict.classification, cpLoss: isBest ? 0 : verdict.cpLoss, isBest: isBest)
    }

    /// The final tally: total points and the most there were.
    public static func total(_ results: [GuessResult]) -> (points: Int, max: Int) {
        (results.reduce(0) { $0 + $1.points }, results.count * maxPoints)
    }
}
