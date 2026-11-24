import Foundation

/// Pure state machine for solving one puzzle: the UI feeds it moves and plays out what it
/// returns. One wrong move fails the attempt (Lichess rule); `retry()` starts over from the
/// puzzle position. Any checkmate is accepted where the expected move mates.
public struct PuzzleSolver: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        /// The setup move has not been played yet (call `playSetup()`).
        case setup
        /// Waiting for the solver's move.
        case solving
        /// The solver's move was right; the opponent's reply is due (call `playReply()`).
        case replying
        case solved
        case failed
    }

    public enum Outcome: Sendable, Equatable {
        /// Not a legal move in this position, or not the solver's turn: nothing changed.
        case illegal
        /// Right move; the puzzle continues with `reply` (already due via `playReply()`).
        case correct(reply: String)
        case solved
        case wrong
    }

    public let puzzle: Puzzle
    public private(set) var fen: String
    public private(set) var status: Status
    /// Index in `puzzle.moves` of the next move to be played.
    public private(set) var index: Int
    public private(set) var lastMove: String?
    /// Moves played on the board in this attempt (setup included), for the UI's piece tracker.
    public private(set) var played: [String] = []
    public private(set) var failures = 0
    public private(set) var hintUsed = false
    public private(set) var hintShown = false
    /// The user's wrong move in the failed attempt, if any.
    public private(set) var wrongMove: String?

    public init(puzzle: Puzzle) {
        self.puzzle = puzzle
        fen = puzzle.fen
        index = 0
        status = puzzle.hasSetupMove ? .setup : .solving
    }

    public var solverColor: Piece.Color { puzzle.solverColor }

    /// The move the solver is expected to play now.
    public var expectedMove: String? {
        status == .solving || status == .failed ? puzzle.moves[safe: index] : nil
    }

    /// `expectedMove` in SAN, from the position it is played in. After a failure that is the
    /// step that went wrong (a later move of a multi-move puzzle), not the key move.
    public var expectedSan: String? {
        guard let move = expectedMove,
              let fen = Rules.fen(startFen: puzzle.fen, moves: status == .failed ? Array(played.dropLast()) : played)
        else { return nil }
        return Rules.apply(uci: move, to: fen)?.san
    }

    /// The failed attempt went wrong on the puzzle's first solver move (the key move).
    public var failedOnKeyMove: Bool { status == .failed && index == puzzle.firstSolverIndex }

    /// Hint: the from-square of the expected move.
    public var hintSquare: Square? {
        guard hintShown, let move = expectedMove else { return nil }
        return Square(String(move.prefix(2)))
    }

    /// Solved on the first attempt without a hint: the SRS "success".
    public var solvedClean: Bool { status == .solved && failures == 0 && !hintUsed }

    /// Plays the opponent's setup move; returns it, or nil when there is none to play.
    @discardableResult
    public mutating func playSetup() -> String? {
        guard status == .setup, let move = puzzle.moves.first, advance(move) else { return nil }
        status = .solving
        return move
    }

    public mutating func submit(_ uci: String) -> Outcome {
        guard status == .solving, let expected = puzzle.moves[safe: index],
              let applied = Rules.apply(uci: uci, to: fen) else { return .illegal }
        if uci == expected || isAlternativeMate(uci, applied: applied, expected: expected) {
            _ = advance(uci, applied: applied)
            if uci != expected || index >= puzzle.moves.count || puzzle.endsAfterKeyMove {
                status = .solved
                return .solved
            }
            status = .replying
            return .correct(reply: puzzle.moves[index])
        }
        // A wrong move is shown on the board, so the failure is visible; retry undoes it.
        _ = advance(uci, applied: applied)
        wrongMove = uci
        failures += 1
        status = .failed
        index -= 1
        return .wrong
    }

    /// Plays the opponent's reply after a correct move; returns it.
    @discardableResult
    public mutating func playReply() -> String? {
        guard status == .replying, let move = puzzle.moves[safe: index], advance(move) else { return nil }
        status = index >= puzzle.moves.count ? .solved : .solving
        hintShown = false
        return move
    }

    /// After a solve of an own-mistake puzzle: plays the next move of the engine line as a
    /// demonstration (nothing is asked of the solver); nil when there is none left.
    @discardableResult
    public mutating func playDemo() -> String? {
        guard status == .solved, puzzle.endsAfterKeyMove, let move = puzzle.moves[safe: index], advance(move) else { return nil }
        return move
    }

    public mutating func showHint() {
        guard status == .solving else { return }
        hintShown = true
        hintUsed = true
    }

    /// Starts the attempt over from the position the solver faces (setup already played).
    public mutating func retry() {
        let keepFailures = failures, keepHint = hintUsed
        self = PuzzleSolver(puzzle: puzzle)
        playSetup()
        failures = keepFailures
        hintUsed = keepHint
    }

    // MARK: Private

    private func isAlternativeMate(_ uci: String, applied: AppliedMove, expected: String) -> Bool {
        guard let expectedApplied = Rules.apply(uci: expected, to: fen),
              case .checkmate = Rules.state(fen: expectedApplied.fenAfter, history: [], startFen: expectedApplied.fenAfter)
        else { return false }
        if case .checkmate = Rules.state(fen: applied.fenAfter, history: [], startFen: applied.fenAfter) { return true }
        return false
    }

    private mutating func advance(_ uci: String) -> Bool {
        guard let applied = Rules.apply(uci: uci, to: fen) else { return false }
        return advance(uci, applied: applied)
    }

    private mutating func advance(_ uci: String, applied: AppliedMove) -> Bool {
        fen = applied.fenAfter
        lastMove = uci
        played.append(uci)
        index += 1
        return true
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
