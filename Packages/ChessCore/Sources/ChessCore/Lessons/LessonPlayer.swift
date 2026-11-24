import Foundation

/// Pure state machine for playing one lesson.
///
/// Scripted lessons (`.line`, `.mate`) check each user move against the script: a wrong
/// move is not played, it raises the hint level instead (1: the piece to move, 2: the whole
/// move). Free-play endgames (`.win`, `.draw`) accept any legal move and ask the caller for
/// the engine's reply via `.opponentTurn`.
public struct LessonPlayer: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case userTurn
        /// A scripted move of the other side is due: call `playAuto()`.
        case autoTurn
        /// Free play: the engine's reply is due; pass it to `applyOpponent(_:)`.
        case opponentTurn
        case completed
        /// Free play ended without reaching the goal.
        case failed(reason: String)
    }

    public enum Outcome: Sendable, Equatable {
        case illegal
        case wrong
        /// Accepted; check `status` for what comes next.
        case accepted
    }

    public let lesson: Lesson
    public private(set) var fen: String
    public private(set) var status: Status
    public private(set) var stepIndex = 0
    public private(set) var played: [String] = []
    public private(set) var lastMove: String?
    /// 0 none, 1 show the piece to move, 2 show the move. Resets after every correct move.
    public private(set) var hintLevel = 0
    /// The text for the explanation card: the summary first, then each move's note.
    public private(set) var explanation: String

    public init(lesson: Lesson) {
        self.lesson = lesson
        fen = lesson.startFen
        explanation = lesson.summary
        status = .userTurn
        settleTurn()
    }

    public var isScripted: Bool { lesson.goal == .line || lesson.goal == .mate }

    /// The user's next scripted move, if any.
    public var expectedMove: String? {
        guard isScripted, status == .userTurn, let step = lesson.steps[safe: stepIndex] else { return nil }
        return step.uci
    }

    /// User moves made so far and in total (scripted lessons), for a progress readout.
    public var userMovesDone: Int { lesson.steps.prefix(stepIndex).filter { $0.side == .user }.count }
    public var userMovesTotal: Int { lesson.steps.filter { $0.side == .user }.count }

    public mutating func submit(_ uci: String) -> Outcome {
        guard status == .userTurn, let applied = Rules.apply(uci: uci, to: fen) else { return .illegal }
        if isScripted {
            guard let step = lesson.steps[safe: stepIndex] else { return .illegal }
            let mates = lesson.goal == .mate && Rules.isCheckmate(fen: applied.fenAfter)
            guard uci == step.uci || mates else {
                hintLevel = min(hintLevel + 1, 2)
                return .wrong
            }
            play(uci, applied)
            stepIndex += 1
            hintLevel = 0
            if !step.explanation.isEmpty { explanation = step.explanation }
            if mates { stepIndex = lesson.steps.count }
            settleTurn()
        } else {
            play(uci, applied)
            settleFreePlay(userJustMoved: true)
        }
        return .accepted
    }

    /// Plays the scripted reply; returns it.
    @discardableResult
    public mutating func playAuto() -> String? {
        guard status == .autoTurn, let step = lesson.steps[safe: stepIndex],
              let applied = Rules.apply(uci: step.uci, to: fen) else { return nil }
        play(step.uci, applied)
        stepIndex += 1
        settleTurn()
        return step.uci
    }

    /// Applies the engine's reply in free play. Returns false if it is not legal here.
    @discardableResult
    public mutating func applyOpponent(_ uci: String) -> Bool {
        guard status == .opponentTurn, let applied = Rules.apply(uci: uci, to: fen) else { return false }
        play(uci, applied)
        settleFreePlay(userJustMoved: false)
        return true
    }

    /// Raises the hint by one level (toolbar hint in scripted lessons).
    public mutating func hint() {
        guard isScripted, status == .userTurn else { return }
        hintLevel = min(hintLevel + 1, 2)
    }

    public mutating func restart() {
        self = LessonPlayer(lesson: lesson)
    }

    // MARK: Private

    private mutating func play(_ uci: String, _ applied: AppliedMove) {
        fen = applied.fenAfter
        played.append(uci)
        lastMove = uci
    }

    private mutating func settleTurn() {
        guard isScripted else {
            status = sideToMove == lesson.userColor ? .userTurn : .opponentTurn
            return
        }
        guard let step = lesson.steps[safe: stepIndex] else {
            status = .completed
            return
        }
        status = step.side == .user ? .userTurn : .autoTurn
    }

    private mutating func settleFreePlay(userJustMoved: Bool) {
        switch Rules.state(fen: fen, history: played, startFen: lesson.startFen) {
        case .checkmate(let winner):
            status = winner == lesson.userColor && lesson.goal == .win
                ? .completed : .failed(reason: winner == lesson.userColor ? "Checkmate, but this one is a draw to hold." : "Checkmated.")
        case .stalemate, .insufficientMaterial, .threefold, .fiftyMove:
            status = lesson.goal == .draw ? .completed : .failed(reason: drawReason)
        case .active, .check:
            status = userJustMoved ? .opponentTurn : .userTurn
        }
    }

    private var drawReason: String {
        switch Rules.state(fen: fen, history: played, startFen: lesson.startFen) {
        case .stalemate: "Stalemate: the game is drawn."
        case .insufficientMaterial: "Not enough material left to mate."
        case .threefold: "Draw by repetition."
        case .fiftyMove: "Draw by the fifty-move rule."
        default: "The game is drawn."
        }
    }

    private var sideToMove: Piece.Color {
        fen.split(separator: " ").dropFirst().first == "b" ? .black : .white
    }
}
