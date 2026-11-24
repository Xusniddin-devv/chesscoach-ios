import Foundation

public enum GameAnalyzerError: Error, Equatable {
    case illegalMove(ply: Int, uci: String)
    case invalidStartFen
}

/// What to search in one game and how to turn the searches into a `GameAnalysis`.
///
/// Full: every position at a fixed depth, MultiPV 2 (review grade). Quick: node-limited,
/// MultiPV 1, the opening-book prefix not searched (those plies are book) and nothing after
/// `quickMaxPly`. One request per position, so a caller can stop or yield between positions.
public struct AnalysisPlan: Sendable {
    public enum Mode: Sendable, Equatable {
        case full(depth: Int)
        case quick(nodes: Int, maxPly: Int)
    }

    /// Bulk review depth (global constraints).
    public static let fullDepth = 14
    /// Quick pass node limit. iPhone 17 Pro simulator, 4 threads (onboarding): 30k nodes
    /// 10.7 ms, 50k 19.1 ms a position, so 40k lands mid-way in the 10-20 ms target; with the
    /// app's 1 thread (background, after onboarding) ~45 ms. Tier, weaknesses and plan only
    /// need the big swings.
    public static let quickNodes = 40_000
    /// Quick pass stops here: long endgames add time, rarely a new habit.
    public static let quickMaxPly = 120

    public static let quick = Mode.quick(nodes: quickNodes, maxPly: quickMaxPly)
    public static let full = Mode.full(depth: fullDepth)

    public let startFen: String
    public let moves: [String]
    public let mode: Mode
    /// FEN after each ply; index 0 is the start.
    public let fens: [String]
    public let sans: [String]
    public let movers: [Piece.Color]
    /// Plies covered: all of them for full, at most `maxPly` for quick.
    public let plies: Int
    /// Quick only: the first `bookPlies` plies stay inside the opening book. Only the last book
    /// position is searched; the earlier ones share its score and the plies are graded book.
    public let bookPlies: Int
    /// Position indices to search, in order.
    public let positions: [Int]

    public init(startFen: String, moves: [String], mode: Mode) throws {
        var fens = [startFen]
        var sans: [String] = []
        var movers: [Piece.Color] = []
        for (i, uci) in moves.enumerated() {
            guard let applied = Rules.apply(uci: uci, to: fens[i]) else {
                throw GameAnalyzerError.illegalMove(ply: i, uci: uci)
            }
            movers.append(Self.sideToMove(fen: fens[i]))
            sans.append(applied.san)
            fens.append(applied.fenAfter)
        }
        self.startFen = startFen
        self.moves = moves
        self.mode = mode
        self.fens = fens
        self.sans = sans
        self.movers = movers
        switch mode {
        case .full:
            plies = moves.count
            bookPlies = 0
        case .quick(_, let maxPly):
            plies = min(moves.count, max(0, maxPly))
            var book = 0
            while book < plies, OpeningBook.lookup(fen: fens[book + 1]) != nil { book += 1 }
            bookPlies = book
        }
        positions = Array(bookPlies...plies)
    }

    public var pass: AnalysisPass {
        if case .full = mode { return .full }
        return .quick
    }

    public func request(for position: Int) -> AnalysisRequest {
        switch mode {
        case .full(let depth):
            AnalysisRequest(startFen: startFen, moves: Array(moves.prefix(position)), depth: depth, multiPV: 2)
        case .quick(let nodes, _):
            AnalysisRequest(startFen: startFen, moves: Array(moves.prefix(position)), depth: 0, multiPV: 1, nodes: nodes)
        }
    }

    /// The analysis from one result per position in `positions` (a missing one counts as 0.00).
    /// `evalSource` marks evals that came from a platform instead of this app's engine; such an
    /// analysis is always `.quick`, so Review re-analyses it with its own engine.
    public func assemble(_ results: [Int: AnalysisResult], evalSource: String? = nil) -> GameAnalysis {
        let zero = AnalysisResult(bestMove: "", lines: [PVLine(multipv: 1, depth: 0, score: Score(cp: 0), pv: [])])
        // Book positions share the last book position's White-relative score.
        let bookWhiteCp = results[bookPlies].map {
            toCp($0.lines.first?.score ?? Score(cp: 0), sideToMove: Self.sideToMove(fen: fens[bookPlies]))
        }
        let filled: [AnalysisResult] = (0...plies).map { i in
            if let r = results[i] { return r }
            if i < bookPlies, let cp = bookWhiteCp {
                let stm = Self.sideToMove(fen: fens[i])
                let score = Score(cp: Int((stm == .white ? cp : -cp).rounded()))
                return AnalysisResult(bestMove: "", lines: [PVLine(multipv: 1, depth: 0, score: score, pv: [])])
            }
            return zero
        }
        let whiteWin = (0...plies).map { i -> Double in
            let score = filled[i].lines.first?.score ?? Score(cp: 0)
            let w = winPercent(toCp(score, sideToMove: Self.sideToMove(fen: fens[i])))
            return w.isFinite ? min(max(w, 0), 100) : 50
        }
        let verdicts = (0..<plies).map { i -> Verdict in
            var v = classifyPlayed(PlayedMoveInput(
                fenBefore: fens[i], fenAfter: fens[i + 1], playedUci: moves[i], playedSan: sans[i],
                mover: movers[i], ply: i + 1, before: filled[i], after: filled[i + 1]))
            if i < bookPlies {
                v.classification = .book
                v.motifs = []
            }
            return v
        }
        let accuracy = gameAccuracy(whiteWin: whiteWin, movers: Array(movers.prefix(plies)))
        let depth: Int
        let nodes: Int?
        switch mode {
        case .full(let d) where evalSource == nil:
            depth = d
            nodes = nil
        case .full:
            depth = 0
            nodes = nil
        case .quick(let n, _):
            depth = results.values.compactMap { $0.lines.first?.depth }.max() ?? 0
            nodes = n
        }
        return GameAnalysis(depth: depth, verdicts: verdicts, whiteWin: whiteWin,
                            accuracyWhite: accuracy.white.isFinite ? accuracy.white : 100,
                            accuracyBlack: accuracy.black.isFinite ? accuracy.black : 100,
                            pass: evalSource == nil ? pass : .quick, evalSource: evalSource, nodes: nodes)
    }

    static func sideToMove(fen: String) -> Piece.Color {
        fen.split(separator: " ").dropFirst().first == "b" ? .black : .white
    }
}

/// Bulk both-colour analysis of one finished game: every planned position is searched once,
/// then each ply is classified from the search before and after it.
public struct GameAnalyzer: Sendable {
    public let engine: any ChessEngine
    public let mode: AnalysisPlan.Mode

    public var depth: Int {
        if case .full(let d) = mode { return d }
        return 0
    }

    public init(engine: any ChessEngine, depth: Int = 14) {
        self.engine = engine
        self.mode = .full(depth: depth)
    }

    public init(engine: any ChessEngine, mode: AnalysisPlan.Mode) {
        self.engine = engine
        self.mode = mode
    }

    /// Throws on any engine error (the caller may retry) and propagates `CancellationError`.
    /// `progress(done, total)` fires after each searched position; total is the number of
    /// positions searched (`moves.count + 1` for a full pass).
    public func analyze(startFen: String, moves: [String],
                        progress: @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> GameAnalysis {
        let plan = try AnalysisPlan(startFen: startFen, moves: moves, mode: mode)
        var results: [Int: AnalysisResult] = [:]
        for (n, position) in plan.positions.enumerated() {
            try Task.checkCancellation()
            results[position] = try await engine.analyze(plan.request(for: position))
            progress(n + 1, plan.positions.count)
        }
        return plan.assemble(results)
    }
}
