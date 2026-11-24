import SwiftUI
import OSLog
import Observation
import ChessCore

/// "Guess the move" on a saved, analysed game: the user picks a side, and at each of that
/// side's moves the board waits for a guess. The guess is scored against the engine
/// (`GuessScoring`: best 3, within 50 cp 2, within 150 cp 1) from the game's saved analysis;
/// a move the analysis doesn't cover is searched (depth 14, MultiPV 3). Then the reveal
/// shows the guess, the game's move and the best move; the other side's moves play themselves.
@MainActor @Observable
final class GuessModel {
    enum Phase: Equatable {
        /// Picking the side to guess.
        case choosing
        /// The board waits for a guess at `ply`.
        case guessing
        /// The guess is being scored.
        case grading(String)
        /// The guess, the game's move and the best move.
        case revealed(GuessResult)
        /// Scoring stopped on an engine error; `retry()`.
        case failed(String)
        /// All guessed: the score.
        case finished
    }

    let snapshot: GameSnapshot
    let analysis: GameAnalysis
    let opponentName: String
    let userAvatar: String
    let opponentAvatar: String?

    private(set) var phase: Phase = .choosing
    /// The side being guessed.
    var side: Piece.Color
    var orientation: Piece.Color
    /// The ply to guess (1-based): the board shows the position before it.
    private(set) var ply = 0
    private(set) var results: [GuessResult] = []

    @ObservationIgnored private let engine: any ChessEngine
    @ObservationIgnored private var gradeTask: Task<Void, Never>?
    private static let log = Logger(subsystem: "uz.xq.chessc", category: "guess")

    init(snapshot: GameSnapshot, analysis: GameAnalysis, opponentName: String, userAvatar: String,
         opponentAvatar: String?, engine: any ChessEngine) {
        self.snapshot = snapshot
        self.analysis = analysis
        self.opponentName = opponentName
        self.userAvatar = userAvatar
        self.opponentAvatar = opponentAvatar
        self.engine = engine
        side = snapshot.userColor
        orientation = snapshot.userColor
    }

    // MARK: Plies

    /// The plies `color` played (1-based), from the analysis' movers.
    func plies(for color: Piece.Color) -> [Int] {
        analysis.verdicts.filter { $0.mover == color && $0.ply <= snapshot.moves.count }.map(\.ply).sorted()
    }

    var guessPlies: [Int] { plies(for: side) }

    /// "3 / 18" while guessing.
    var progress: (done: Int, total: Int) {
        let plies = guessPlies
        let index = plies.firstIndex(of: ply) ?? plies.count
        let done = if case .revealed = phase { index + 1 } else { index }
        return (min(done, plies.count), plies.count)
    }

    func name(of color: Piece.Color) -> String { color == snapshot.userColor ? "You" : opponentName }

    // MARK: Flow

    func start() {
        results = []
        orientation = side
        guard let first = guessPlies.first else { phase = .finished; return }
        ply = first
        phase = .guessing
    }

    /// A move on the board while guessing. Returns false when not accepted.
    @discardableResult
    func guess(_ uci: String) -> Bool {
        guard phase == .guessing, let applied = Rules.apply(uci: uci, to: displayedFen) else { return false }
        phase = .grading(applied.san)
        grade(uci)
        return true
    }

    private func grade(_ uci: String) {
        let ply = ply
        let snapshot = snapshot
        let analysis = analysis
        let engine = engine
        gradeTask = Task { [weak self] in
            do {
                let result = try await GuessScoring.grade(
                    guess: uci, ply: ply, startFen: snapshot.startFen, moves: snapshot.moves,
                    analysis: analysis, engine: engine, depth: ReviewModel.depth)
                guard let self, !Task.isCancelled, self.ply == ply else { return }
                if let result {
                    self.results.append(result)
                    self.phase = .revealed(result)
                } else {
                    self.phase = .guessing
                }
            } catch is CancellationError {
            } catch {
                Self.log.error("Guess scoring failed: \(String(describing: error), privacy: .public)")
                guard let self, self.ply == ply else { return }
                self.phase = .failed(uci)
            }
        }
    }

    func retry() {
        guard case .failed(let uci) = phase else { return }
        phase = .grading(Rules.apply(uci: uci, to: displayedFen)?.san ?? uci)
        grade(uci)
    }

    /// After the reveal (or skipping a move): the side's next move, or the score.
    func next() {
        let plies = guessPlies
        guard let index = plies.firstIndex(of: ply), index + 1 < plies.count else {
            phase = .finished
            return
        }
        ply = plies[index + 1]
        phase = .guessing
    }

    /// Moves on without guessing (not scored).
    func skip() {
        guard phase == .guessing || isFailed else { return }
        gradeTask?.cancel()
        next()
    }

    /// Ends now and shows the score so far.
    func finish() {
        gradeTask?.cancel()
        phase = .finished
    }

    func cancel() { gradeTask?.cancel() }

    /// Back to picking the side ("Try again").
    func restart() {
        gradeTask?.cancel()
        results = []
        ply = 0
        phase = .choosing
    }

    private var isFailed: Bool { if case .failed = phase { true } else { false } }

    var isRevealed: Bool { if case .revealed = phase { true } else { false } }
    var revealed: GuessResult? { if case .revealed(let result) = phase { result } else { nil } }

    // MARK: Board

    var displayedFen: String { position(after: max(0, ply - 1)).fen }
    var displayedTracker: PieceTracker { position(after: max(0, ply - 1)).tracker }

    @ObservationIgnored private var positionCache: (ply: Int, fen: String, tracker: PieceTracker)?

    private func position(after count: Int) -> (fen: String, tracker: PieceTracker) {
        if let cached = positionCache, cached.ply == count { return (cached.fen, cached.tracker) }
        var fen = snapshot.startFen
        var tracker = PieceTracker(fen: fen)
        for uci in snapshot.moves.prefix(count) {
            guard let applied = Rules.apply(uci: uci, to: fen) else { break }
            tracker.apply(uci, fenBefore: fen)
            fen = applied.fenAfter
        }
        positionCache = (count, fen, tracker)
        return (fen, tracker)
    }

    /// The other side's move that led here.
    var lastMove: (Square, Square)? {
        guard ply > 1, phase != .choosing else { return nil }
        return Self.squares(snapshot.moves[ply - 2])
    }

    var interactive: Bool { phase == .guessing }

    /// On the reveal, each move as an arrow in its class colour: the guess, the game's move,
    /// the best move (one arrow when they are the same move).
    var arrows: [(Square, Square, Color)] {
        guard let result = revealed else { return [] }
        var seen = Set<String>()
        var arrows: [(Square, Square, Color)] = []
        for (uci, moveClass) in [(result.bestUci, MoveClass.best), (result.playedUci, result.playedClass),
                                 (result.guessUci, result.guessClass)] where seen.insert(uci).inserted {
            if let squares = Self.squares(uci) { arrows.append((squares.0, squares.1, DS.Color.moveClass(moveClass))) }
        }
        return arrows
    }

    var badges: [Square: MoveClass] {
        guard let result = revealed, let to = Self.squares(result.guessUci)?.1 else { return [:] }
        return [to: result.guessClass]
    }

    var statusText: String {
        switch phase {
        case .choosing: return "Pick a side to guess"
        case .guessing:
            let number = (ply + 1) / 2
            return "Move \(number) · what would \(side == snapshot.userColor ? "you" : opponentName) play?"
        case .grading(let san): return "Checking \(san)…"
        case .failed: return "Couldn't check that move"
        case .revealed(let result): return "\(result.guessSan) · \(result.guessClass.label) \(result.guessClass.glyph)"
        case .finished: return ""
        }
    }

    // MARK: Score

    var total: (points: Int, max: Int) { GuessScoring.total(results) }

    /// What the game's own moves would have scored on the same plies.
    var gameTotal: Int {
        results.reduce(0) { sum, result in
            let verdict = analysis.verdicts.first { $0.ply == result.ply }
            return sum + GuessScoring.points(isBest: result.playedUci == result.bestUci, cpLoss: verdict?.cpLoss ?? 0)
        }
    }

    var bestCount: Int { results.filter { $0.points == GuessScoring.maxPoints }.count }

    // MARK: Bars

    func bar(for color: Piece.Color) -> PlayerBarModel {
        let tray = BoardMaterial.tray(for: color, fen: displayedFen)
        let isUser = color == snapshot.userColor
        return PlayerBarModel(name: name(of: color), elo: nil, avatarAsset: isUser ? userAvatar : opponentAvatar,
                              captured: tray.captured, materialLead: tray.lead)
    }

    private static func squares(_ uci: String) -> (Square, Square)? {
        guard uci.count >= 4 else { return nil }
        return (Square(String(uci.prefix(2))), Square(String(uci.dropFirst(2).prefix(2))))
    }
}
