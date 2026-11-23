import Foundation
import Observation

/// One game against a bot: the authoritative board, an ordered grading queue for the user's
/// moves, the bot's replies, Training-mode interrupts, take-backs and the end of the game.
///
/// Board state lives only in the stored properties below and is changed synchronously.
/// Async work never reads it from a captured copy: each grade job carries its own snapshot,
/// and every async result is checked against `generation` before it touches state.
@MainActor @Observable
public final class GameSession {
    public enum Phase: Equatable, Sendable {
        case userTurn, botThinking, grading, interrupted(Verdict), over(GameResult, reason: GameState?), engineError
    }

    public let bot: Bot
    public let userColor: Piece.Color
    public let mode: PlayMode
    public let playerRating: Int
    public let analysisDepth: Int
    public let startFen: String

    public private(set) var fen: String
    public private(set) var moves: [String] = []
    public private(set) var sans: [String] = []
    public private(set) var tracker: PieceTracker
    /// Grades of the user's moves, keyed by ply (1-based: the move's index in `moves` plus one).
    public private(set) var verdicts: [Int: Verdict] = [:]
    public private(set) var phase: Phase
    public private(set) var lastMove: (from: Square, to: Square)?
    public private(set) var bestArrow: (from: Square, to: Square)?

    private struct GradeJob: Sendable {
        var startFen: String
        var fenBefore: String
        var fenAfter: String
        var historyBefore: [String]
        var historyAfter: [String]
        var uci: String
        var san: String
        var mover: Piece.Color
        var ply: Int
        var generation: Int
    }

    private static let analysisVersion = 1

    @ObservationIgnored private let engine: any ChessEngine
    @ObservationIgnored private let clock: any _Concurrency.Clock<Duration>
    @ObservationIgnored private let jitter: () -> Double
    @ObservationIgnored private let id = UUID()
    @ObservationIgnored private let startedAt = Date()

    /// Bumped by `takeBack()`; async results from an older generation are dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var gradeQueue: [GradeJob] = []
    @ObservationIgnored private var drainTask: Task<Void, Never>?
    @ObservationIgnored private var botTask: Task<Void, Never>?
    @ObservationIgnored private var interruptingVerdict: Verdict?
    @ObservationIgnored private var hasEngineError = false
    @ObservationIgnored private var ending: (result: GameResult, reason: GameState?)?

    public init(bot: Bot, userColor: Piece.Color, mode: PlayMode, engine: any ChessEngine,
                playerRating: Int = PlayerProfile.defaultRating, analysisDepth: Int = 16,
                startFen: String = Rules.startFen,
                clock: any _Concurrency.Clock<Duration> = ContinuousClock(),
                jitter: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.bot = bot
        self.userColor = userColor
        self.mode = mode
        self.engine = engine
        self.playerRating = playerRating
        self.analysisDepth = analysisDepth
        self.startFen = startFen
        self.clock = clock
        self.jitter = jitter
        fen = startFen
        tracker = PieceTracker(fen: startFen)
        phase = Self.sideToMove(startFen) == userColor ? .userTurn : .botThinking
        endIfTerminal()
    }

    // MARK: Public API

    /// Starts the game: requests the bot's move if the bot is to move.
    public func start() {
        advance()
    }

    /// Plays the user's move if it is legal and it is the user's turn. Board state changes
    /// immediately; the grade runs later from the job's own snapshot.
    @discardableResult
    public func userMove(_ uci: String) -> Bool {
        guard phase == .userTurn, let applied = Rules.apply(uci: uci, to: fen) else { return false }
        let fenBefore = fen
        let historyBefore = moves
        apply(uci, applied)
        bestArrow = nil
        gradeQueue.append(GradeJob(
            startFen: startFen, fenBefore: fenBefore, fenAfter: fen,
            historyBefore: historyBefore, historyAfter: moves,
            uci: uci, san: applied.san, mover: userColor, ply: moves.count, generation: generation))
        drainIfNeeded()
        if !endIfTerminal() { advance() }
        return true
    }

    /// Undoes back to the user's previous turn: the user's last move and any bot reply after it.
    public func takeBack() {
        guard let userIndex = moves.indices.last(where: { mover(atIndex: $0) == userColor }) else { return }

        generation += 1
        botTask?.cancel()
        botTask = nil
        drainTask?.cancel()
        drainTask = nil
        // Grades of earlier, kept moves stay valid; re-stamp them for the new generation.
        gradeQueue = gradeQueue.filter { $0.ply <= userIndex }.map {
            var job = $0
            job.generation = generation
            return job
        }
        verdicts = verdicts.filter { $0.key <= userIndex }
        interruptingVerdict = nil
        hasEngineError = false
        ending = nil
        bestArrow = nil

        let kept = Array(moves.prefix(userIndex))
        moves = []
        sans = []
        fen = startFen
        tracker = PieceTracker(fen: startFen)
        lastMove = nil
        for uci in kept {
            guard let applied = Rules.apply(uci: uci, to: fen) else { break }
            apply(uci, applied)
        }

        drainIfNeeded()
        advance()
    }

    /// Shows the interrupting verdict's best move as an arrow.
    public func showBest() {
        guard case .interrupted(let verdict) = phase else { return }
        bestArrow = Self.squares(verdict.bestMove)
    }

    public func continueAfterInterrupt() {
        guard case .interrupted = phase else { return }
        interruptingVerdict = nil
        bestArrow = nil
        advance()
    }

    public func resign() {
        guard ending == nil else { return }
        botTask?.cancel()
        botTask = nil
        interruptingVerdict = nil
        end(userColor == .white ? .blackWins : .whiteWins, reason: nil)
    }

    /// Training only, on the user's turn: shows the engine's best move in the current position.
    public func hint() async {
        guard mode == .training, phase == .userTurn else { return }
        let gen = generation
        let ply = moves.count
        let request = AnalysisRequest(startFen: startFen, moves: moves, depth: analysisDepth, multiPV: 1)
        // A failed hint is optional help, not a game step: it leaves the game as it was.
        guard let result = try? await engine.analyze(request),
              gen == generation, ply == moves.count, phase == .userTurn else { return }
        bestArrow = Self.squares(result.bestMove)
    }

    /// From `.engineError`, re-runs what failed: the grade at the head of the queue and/or the bot move.
    public func retry() {
        guard phase == .engineError else { return }
        hasEngineError = false
        drainIfNeeded()
        advance()
    }

    public func snapshot() -> GameSnapshot {
        GameSnapshot(
            id: id, date: startedAt, botId: bot.id, userColor: userColor, mode: mode,
            startFen: startFen, moves: moves, sans: sans, result: ending?.result ?? .ongoing,
            verdicts: verdicts.values.sorted { $0.ply < $1.ply },
            analysisVersion: Self.analysisVersion, playerRatingUsed: playerRating)
    }

    // MARK: Flow

    /// Moves the game on from the current state: user's turn, waiting for a grade,
    /// interrupted, or the bot's turn (starting its search if none is running).
    private func advance() {
        guard ending == nil else { return }
        if hasEngineError {
            phase = .engineError
            return
        }
        if Self.sideToMove(fen) == userColor {
            phase = .userTurn
            return
        }
        if mode == .training {
            if let verdict = interruptingVerdict {
                phase = .interrupted(verdict)
                return
            }
            if let last = moves.indices.last, mover(atIndex: last) == userColor, verdicts[last + 1] == nil {
                phase = .grading
                return
            }
        }
        phase = .botThinking
        if botTask == nil { startBotMove() }
    }

    private func apply(_ uci: String, _ applied: AppliedMove) {
        tracker.apply(uci, fenBefore: fen)
        fen = applied.fenAfter
        moves.append(uci)
        sans.append(applied.san)
        lastMove = Self.squares(uci)
    }

    /// Ends the game if the current position is terminal. Returns true if the game is over.
    @discardableResult
    private func endIfTerminal() -> Bool {
        switch Rules.state(fen: fen, history: moves, startFen: startFen) {
        case .active, .check:
            return false
        case .checkmate(let winner):
            end(winner == .white ? .whiteWins : .blackWins, reason: .checkmate(winner: winner))
        case let reason:
            end(.draw, reason: reason)
        }
        return true
    }

    private func end(_ result: GameResult, reason: GameState?) {
        ending = (result, reason)
        phase = .over(result, reason: reason)
    }

    private func fail() {
        hasEngineError = true
        if ending == nil { phase = .engineError }
    }

    // MARK: Grading queue

    private func drainIfNeeded() {
        guard drainTask == nil, !gradeQueue.isEmpty else { return }
        drainTask = Task { [weak self] in await self?.drain() }
    }

    /// Grades queued jobs strictly one at a time, in order.
    private func drain() async {
        while let job = gradeQueue.first {
            let outcome: Result<Verdict, any Error>
            do {
                outcome = .success(try await Self.grade(job, engine: engine, depth: analysisDepth))
            } catch {
                outcome = .failure(error)
            }
            // A take-back started a new generation (and owns the queue now): drop this result.
            guard job.generation == generation, !Task.isCancelled else { return }
            switch outcome {
            case .success(let verdict):
                gradeQueue.removeFirst()
                verdicts[job.ply] = verdict
                if mode == .training, ending == nil, job.ply == moves.count, interrupts(verdict) {
                    interruptingVerdict = verdict
                }
                advance()
            case .failure(let error):
                drainTask = nil
                if !(error is CancellationError) { fail() }
                return
            }
        }
        drainTask = nil
    }

    private func interrupts(_ verdict: Verdict) -> Bool {
        trainingSeverity(cpLoss: verdict.cpLoss, level: playerRating) >= .mistake || verdict.classification == .miss
    }

    private nonisolated static func grade(_ job: GradeJob, engine: any ChessEngine, depth: Int) async throws -> Verdict {
        let before = try await engine.analyze(
            AnalysisRequest(startFen: job.startFen, moves: job.historyBefore, depth: depth, multiPV: 2))
        let after = try await engine.analyze(
            AnalysisRequest(startFen: job.startFen, moves: job.historyAfter, depth: depth, multiPV: 2))
        return classifyPlayed(PlayedMoveInput(
            fenBefore: job.fenBefore, fenAfter: job.fenAfter, playedUci: job.uci, playedSan: job.san,
            mover: job.mover, ply: job.ply, before: before, after: after))
    }

    // MARK: Bot

    private func startBotMove() {
        let gen = generation
        let request = (startFen: startFen, moves: moves, elo: bot.elo)
        let think = Duration.milliseconds(thinkTimeMs(elo: bot.elo, jitter: jitter()))
        let engine = engine
        let clock = clock
        botTask = Task { [weak self] in
            let outcome: Result<String, any Error>
            do {
                outcome = .success(try await Self.pacedBotMove(
                    engine: engine, clock: clock, startFen: request.startFen, moves: request.moves,
                    elo: request.elo, think: think))
            } catch {
                outcome = .failure(error)
            }
            self?.finishBotMove(outcome, generation: gen)
        }
    }

    private func finishBotMove(_ outcome: Result<String, any Error>, generation gen: Int) {
        guard gen == generation, botTask?.isCancelled == false else { return }
        botTask = nil
        switch outcome {
        case .success(let uci):
            guard let applied = Rules.apply(uci: uci, to: fen) else {
                fail()  // "" (no move) or an illegal move from a non-terminal position
                return
            }
            apply(uci, applied)
            if !endIfTerminal() { advance() }
        case .failure(let error):
            if !(error is CancellationError) { fail() }
        }
    }

    /// Asks for the bot's move, then pads to `think` only if the search finished early.
    private nonisolated static func pacedBotMove<C: _Concurrency.Clock<Duration>>(
        engine: any ChessEngine, clock: C, startFen: String, moves: [String], elo: Int, think: Duration
    ) async throws -> String {
        let started = clock.now
        let uci = try await engine.opponentMove(startFen: startFen, moves: moves, elo: elo)
        let elapsed = started.duration(to: clock.now)
        if elapsed < think {
            try await clock.sleep(for: think - elapsed)
        }
        return uci
    }

    // MARK: Helpers

    private func mover(atIndex index: Int) -> Piece.Color {
        let first = Self.sideToMove(startFen)
        return index.isMultiple(of: 2) ? first : first.opposite
    }

    private nonisolated static func sideToMove(_ fen: String) -> Piece.Color {
        fen.split(separator: " ").dropFirst().first == "b" ? .black : .white
    }

    private nonisolated static func squares(_ uci: String) -> (from: Square, to: Square)? {
        guard uci.count >= 4 else { return nil }
        return (Square(String(uci.prefix(2))), Square(String(uci.dropFirst(2).prefix(2))))
    }
}
