import Foundation

/// One game as a platform hands it over: the PGN plus whatever the platform already worked out.
public struct ImportedGame: Sendable, Equatable {
    public var pgn: String
    /// chess.com `accuracies` (games reviewed there) or Lichess `players.*.analysis.accuracy`.
    public var accuracy: PlatformAccuracy?
    /// Lichess per-ply evals (`analysis`), present when the game was analysed on Lichess.
    public var evals: [PlatformEval]?

    public init(pgn: String, accuracy: PlatformAccuracy? = nil, evals: [PlatformEval]? = nil) {
        self.pgn = pgn
        self.accuracy = accuracy
        self.evals = evals
    }
}

/// The eval after one ply, White's point of view (Lichess `analysis[i]`).
public struct PlatformEval: Sendable, Equatable, Decodable {
    public var cp: Int?
    /// Mate in N for White (> 0) or Black (< 0).
    public var mate: Int?
    /// UCI best move in the position *before* this ply (only on judged plies).
    public var best: String?
    /// SAN line from that position, space separated.
    public var variation: String?

    public init(cp: Int? = nil, mate: Int? = nil, best: String? = nil, variation: String? = nil) {
        self.cp = cp
        self.mate = mate
        self.best = best
        self.variation = variation
    }

    private enum CodingKeys: String, CodingKey { case cp = "eval", mate, best, variation }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cp = try? c.decodeIfPresent(Int.self, forKey: .cp)
        mate = try? c.decodeIfPresent(Int.self, forKey: .mate)
        best = try? c.decodeIfPresent(String.self, forKey: .best)
        variation = try? c.decodeIfPresent(String.self, forKey: .variation)
    }

    var hasScore: Bool { cp != nil || mate != nil }
}

public enum PlatformEvals {
    /// A quick analysis from a platform's per-ply evals, graded with this app's rules, or nil
    /// when the evals don't cover every ply. A game ending in mate or stalemate may lack the
    /// final position's eval (Lichess omits it); it is filled from the rules.
    public static func analysis(startFen: String, moves: [String], evals: [PlatformEval],
                                source: String) -> GameAnalysis? {
        guard !moves.isEmpty,
              let plan = try? AnalysisPlan(startFen: startFen, moves: moves, mode: .full(depth: 0)) else { return nil }
        var evals = evals
        if evals.count == moves.count - 1, let terminal = terminalEval(fen: plan.fens[moves.count]) {
            evals.append(terminal)
        }
        guard evals.count == moves.count, evals.allSatisfy(\.hasScore) else { return nil }

        // Position p (after p plies) is evals[p - 1]; the start takes ply 1's eval.
        var results: [Int: AnalysisResult] = [:]
        for p in 0...moves.count {
            let eval = evals[max(0, p - 1)]
            let stm = AnalysisPlan.sideToMove(fen: plan.fens[p])
            let sign = stm == .white ? 1 : -1
            let score = eval.mate.map { Score(mate: $0 * sign) } ?? Score(cp: (eval.cp ?? 0) * sign)
            // evals[p].best is the best move in position p.
            let next = p < evals.count ? evals[p] : nil
            let best = next?.best.flatMap { Rules.apply(uci: $0, to: plan.fens[p]) != nil ? $0 : nil } ?? ""
            let pv = next?.variation.map { line(san: $0, from: plan.fens[p]) } ?? (best.isEmpty ? [] : [best])
            results[p] = AnalysisResult(bestMove: best, lines: [PVLine(multipv: 1, depth: 0, score: score, pv: pv)])
        }
        return plan.assemble(results, evalSource: source)
    }

    /// Mate 0 / draw for a position with no legal moves, White's point of view.
    static func terminalEval(fen: String) -> PlatformEval? {
        guard Rules.legalMoveCount(fen: fen) == 0 else { return nil }
        // Mate 0 converts to "the side to move is mated" whichever side that is.
        return Rules.isCheckmate(fen: fen) ? PlatformEval(mate: 0) : PlatformEval(cp: 0)
    }

    /// SAN line → UCI moves, stopping at the first one that doesn't parse.
    static func line(san: String, from fen: String) -> [String] {
        var fen = fen
        var out: [String] = []
        for token in san.split(separator: " ") {
            guard let uci = Rules.uci(san: String(token), fen: fen), let applied = Rules.apply(uci: uci, to: fen) else { break }
            out.append(uci)
            fen = applied.fenAfter
        }
        return out
    }
}
