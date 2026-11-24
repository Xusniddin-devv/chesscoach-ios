import SwiftUI
import SwiftData
import Observation
import ChessCore

/// What the solver screen plays: a queue of puzzles and where each came from.
struct PuzzleSessionSetup: Identifiable, Hashable {
    enum Kind: Hashable { case daily, practice, review }

    let id = UUID()
    let kind: Kind
    let title: String
    let puzzles: [Puzzle]
    /// Puzzle id → "bank" | "blunder" (missing = "bank").
    var sources: [String: String] = [:]
    /// The theme the player chose (practice by theme, Fix it): the prompt may name it.
    /// Otherwise themes stay hidden until the puzzle is over (they give the answer away).
    var theme: String? = nil
}

/// Drives the solver screen: wraps `PuzzleSolver`, keeps the piece tracker in step, plays
/// the setup move and the replies with a short delay, and records outcomes (SRS + streak).
@MainActor
@Observable
final class PuzzleSessionModel {
    let setup: PuzzleSessionSetup
    private(set) var index = 0
    private(set) var solver: PuzzleSolver
    private(set) var tracker: PieceTracker
    private(set) var showingSolution = false
    /// Every puzzle in the queue has been played.
    private(set) var finished = false
    private(set) var solvedCount = 0
    /// The first outcome of each puzzle in the queue (nil: not finished yet), for the pips.
    private(set) var outcomes: [Bool?]

    private var context: ModelContext?
    private var recorded = false
    private var generation = 0

    static let setupDelay = Duration.milliseconds(550)
    static let replyDelay = Duration.milliseconds(420)

    init(setup: PuzzleSessionSetup) {
        self.setup = setup
        let first = setup.puzzles.first ?? Puzzle(id: "", fen: Rules.startFen, moves: [], rating: 0, themes: [])
        solver = PuzzleSolver(puzzle: first)
        tracker = PieceTracker(fen: first.fen)
        outcomes = Array(repeating: nil, count: setup.puzzles.count)
    }

    func attach(_ context: ModelContext) { self.context = context }

    var puzzle: Puzzle { solver.puzzle }
    var isLast: Bool { index >= setup.puzzles.count - 1 }
    var orientation: Piece.Color { solver.solverColor }
    var interactive: Bool { solver.status == .solving }

    var lastMove: (Square, Square)? {
        guard let move = solver.lastMove else { return nil }
        return (Square(String(move.prefix(2))), Square(String(move.dropFirst(2).prefix(2))))
    }

    var squareTint: [Square: Color] {
        var tint: [Square: Color] = [:]
        if let hint = solver.hintSquare { tint[hint] = DS.Color.accent }
        if solver.status == .failed, let wrong = solver.wrongMove {
            tint[Square(String(wrong.dropFirst(2).prefix(2)))] = DS.Color.danger
        }
        return tint
    }

    /// The verdict on the board, like Review: the solving move's destination gets the Best
    /// badge, a wrong move's destination a Mistake badge.
    var badges: [Square: MoveClass] {
        switch solver.status {
        case .solved:
            guard let move = solver.lastMove else { return [:] }
            return [Square(String(move.dropFirst(2).prefix(2))): .best]
        case .failed:
            guard let wrong = solver.wrongMove else { return [:] }
            return [Square(String(wrong.dropFirst(2).prefix(2))): .mistake]
        default:
            return [:]
        }
    }

    /// From the player's own game (vs a bank puzzle).
    var isOwnMistake: Bool { setup.sources[puzzle.id] == "blunder" }

    var isOver: Bool { solver.status == .solved || solver.status == .failed }

    var arrows: [(Square, Square, Color)] {
        guard showingSolution, let move = solver.expectedMove else { return [] }
        return [(Square(String(move.prefix(2))), Square(String(move.dropFirst(2).prefix(2))), DS.Color.accent)]
    }

    /// Solver moves found so far and in total, for "Move 1 of 3".
    var moveNumber: Int { min((solver.index - puzzle.firstSolverIndex) / 2 + 1, puzzle.solverMoveCount) }

    // MARK: Flow

    func start() {
        load(at: 0)
    }

    func move(_ uci: String) -> Bool {
        let before = solver.fen
        let outcome = solver.submit(uci)
        switch outcome {
        case .illegal:
            return false
        case .correct:
            tracker.apply(uci, fenBefore: before)
            let gen = generation
            Task {
                try? await Task.sleep(for: Self.replyDelay)
                guard gen == generation else { return }
                let replyBefore = solver.fen
                if let reply = solver.playReply() { tracker.apply(reply, fenBefore: replyBefore) }
            }
        case .solved:
            tracker.apply(uci, fenBefore: before)
            solvedCount += 1
            record(solved: true)
        case .wrong:
            tracker.apply(uci, fenBefore: before)
            record(solved: false)
        }
        return true
    }

    func hint() { solver.showHint() }

    func showSolution() { showingSolution = true }

    func retry() {
        generation += 1
        showingSolution = false
        solver.retry()
        tracker = PieceTracker(fen: solver.fen)
    }

    func next() {
        if isLast { finished = true } else { load(at: index + 1) }
    }

    // MARK: Private

    private func load(at i: Int) {
        guard setup.puzzles.indices.contains(i) else { finished = true; return }
        generation += 1
        index = i
        recorded = false
        showingSolution = false
        solver = PuzzleSolver(puzzle: setup.puzzles[i])
        tracker = PieceTracker(fen: solver.fen)
        guard solver.status == .setup else { return }
        let gen = generation
        Task {
            try? await Task.sleep(for: Self.setupDelay)
            guard gen == generation else { return }
            let before = solver.fen
            if let move = solver.playSetup() { tracker.apply(move, fenBefore: before) }
        }
    }

    /// SRS sees only the first outcome of each puzzle; a solve after a retry still counts
    /// as a solve and as streak activity.
    private func record(solved: Bool) {
        guard let context else { return }
        let id = puzzle.id
        if !recorded {
            recorded = true
            if outcomes.indices.contains(index) { outcomes[index] = solved && solver.solvedClean }
            TrainingStore.recordOutcome(puzzleId: id, source: setup.sources[id] ?? "bank",
                                        clean: solver.solvedClean, solved: solved, in: context)
        } else if solved {
            TrainingStore.recordLateSolve(puzzleId: id, in: context)
        }
        if solved { TrainingStore.recordActivity(in: context) }
    }
}
