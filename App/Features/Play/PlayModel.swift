import SwiftUI
import SwiftData
import Observation
import ChessCore

/// What the bot picker hands to the Play screen. `color` may be `.random`; it is resolved
/// each time a game starts.
struct PlaySetup: Identifiable, Hashable {
    enum ColorChoice: String, CaseIterable, Hashable {
        case white, black, random

        var title: String { rawValue.capitalized }

        func resolve() -> Piece.Color {
            switch self {
            case .white: .white
            case .black: .black
            case .random: Bool.random() ? .white : .black
            }
        }
    }

    let id = UUID()
    let bot: Bot
    let mode: PlayMode
    let color: ColorChoice
}

/// The Play screen's state on top of one `GameSession`: board decorations, the hint,
/// captured material, the game-over summary and saving the finished game.
@MainActor @Observable
final class PlayModel {
    enum Outcome { case won, lost, draw }

    let session: GameSession
    var orientation: Piece.Color
    private(set) var hintUnavailable = false
    private(set) var isHinting = false
    @ObservationIgnored private var saved = false

    init(session: GameSession) {
        self.session = session
        orientation = session.userColor
    }

    convenience init(setup: PlaySetup, hub: EngineHub) {
        self.init(session: hub.makeSession(bot: setup.bot, userColor: setup.color.resolve(), mode: setup.mode))
    }

    var bot: Bot { session.bot }

    func start() { session.start() }

    // MARK: Moves

    /// The board contract: only on the user's turn, with the user's side to move.
    var interactive: Bool {
        session.phase == .userTurn && Position(fen: session.fen)?.sideToMove == session.userColor
    }

    /// Called from the board's gesture, inside its animation transaction, so the session's
    /// tracker changes in the same transaction and a dropped piece does not jump back.
    func move(_ uci: String) -> Bool {
        hintUnavailable = false
        return session.userMove(uci)
    }

    func hint() async {
        hintUnavailable = false
        isHinting = true
        let shown = await session.hint()
        isHinting = false
        hintUnavailable = !shown
    }

    func flip() { orientation = orientation.opposite }

    // MARK: Board decorations

    var interruption: Verdict? {
        if case .interrupted(let verdict) = session.phase { return verdict }
        return nil
    }

    private var interruptedSquare: Square? {
        interruption.map { Square(String($0.uci.dropFirst(2).prefix(2))) }
    }

    var squareTint: [Square: Color] {
        guard let verdict = interruption, let square = interruptedSquare else { return [:] }
        return [square: DS.Color.moveClass(verdict.classification)]
    }

    var badges: [Square: MoveClass] {
        guard let verdict = interruption, let square = interruptedSquare else { return [:] }
        return [square: verdict.classification]
    }

    var arrows: [(Square, Square, Color)] {
        session.bestArrow.map { [($0.from, $0.to, DS.Color.accent)] } ?? []
    }

    /// White-relative eval after the latest graded move; even until the first grade.
    var whiteCp: Double {
        Double(session.verdicts.max { $0.key < $1.key }?.value.evalWhiteCp ?? 0)
    }

    // MARK: Captured material

    private static let startCounts: [Piece.Kind: Int] = [.pawn: 8, .knight: 2, .bishop: 2, .rook: 2, .queen: 1]
    private static let trayOrder: [Piece.Kind] = [.pawn, .knight, .bishop, .rook, .queen]

    private var onBoard: [Piece] { Position(fen: session.fen)?.pieces ?? [] }

    /// Pieces `color` has taken, cheapest first (promotions can hide a capture; good enough for a tray).
    func captured(by color: Piece.Color) -> [Piece] {
        let pieces = onBoard
        return Self.trayOrder.flatMap { kind -> [Piece] in
            let left = pieces.filter { $0.color == color.opposite && $0.kind == kind }.count
            let missing = max(0, (Self.startCounts[kind] ?? 0) - left)
            return Array(repeating: Piece(kind, color: color.opposite, square: .a1), count: missing)
        }
    }

    /// Material `color` is ahead by, in pawns (0 when level or behind).
    func materialLead(for color: Piece.Color) -> Int {
        let pieces = onBoard.filter { $0.kind != .king }
        let own = pieces.filter { $0.color == color }.map { pieceValue($0.kind) }.reduce(0, +)
        let other = pieces.filter { $0.color != color }.map { pieceValue($0.kind) }.reduce(0, +)
        return max(0, own - other)
    }

    // MARK: Game over

    var isOver: Bool {
        if case .over = session.phase { return true }
        return false
    }

    var outcome: Outcome? {
        guard case .over(let result, _) = session.phase else { return nil }
        switch result {
        case .draw: return .draw
        case .whiteWins: return session.userColor == .white ? .won : .lost
        case .blackWins: return session.userColor == .black ? .won : .lost
        case .ongoing: return nil
        }
    }

    var endReason: String {
        guard case .over(_, let reason) = session.phase else { return "" }
        switch reason {
        case .checkmate: return "Checkmate"
        case .stalemate: return "Stalemate"
        case .insufficientMaterial: return "Insufficient material"
        case .threefold: return "Threefold repetition"
        case .fiftyMove: return "Fifty-move rule"
        case nil: return "You resigned"
        case .active, .check: return ""
        }
    }

    private var userVerdicts: [Verdict] {
        session.verdicts.values.filter { $0.mover == session.userColor }
    }

    /// Nil while grades are still running or when the user has no graded move.
    var accuracy: Double? {
        guard session.pendingGradeCount == 0 else { return nil }
        return userAccuracy(verdicts: userVerdicts, userColor: session.userColor)
    }

    func count(_ classes: Set<MoveClass>) -> Int {
        userVerdicts.filter { classes.contains($0.classification) }.count
    }

    /// The user played at least one move (a game with none is not worth keeping).
    var hasUserMoves: Bool {
        session.moves.indices.contains { index in
            let first = Position(fen: session.startFen)?.sideToMove ?? .white
            return (index.isMultiple(of: 2) ? first : first.opposite) == session.userColor
        }
    }

    // MARK: Saving

    /// Stores the game once, after its last grades are in (`finalSnapshot`, never `snapshot()`).
    func save(in context: ModelContext) async throws {
        guard !saved else { return }
        saved = true
        let snapshot = await session.finalSnapshot()
        context.insert(try GameRecord(snapshot: snapshot))
        try context.save()
    }
}
