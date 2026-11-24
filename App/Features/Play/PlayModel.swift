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
    /// The user's avatar in the bar (their tier's piece).
    var userAvatar = RatingTier.pawn.avatarAsset
    private(set) var hintUnavailable = false
    private(set) var isHinting = false
    private(set) var isSaved = false
    private(set) var isSaving = false
    /// The saved game's id (Review opens it from the result panel).
    private(set) var savedGameID: UUID?
    /// Writes a snapshot to the store; replaceable in tests.
    @ObservationIgnored var persist: @MainActor (GameSnapshot, ModelContext) throws -> Void = PlayModel.insertRecord

    init(session: GameSession) {
        self.session = session
        orientation = session.userColor
    }

    convenience init(setup: PlaySetup, hub: EngineHub) {
        self.init(session: hub.makeSession(bot: setup.bot, userColor: setup.color.resolve(), mode: setup.mode))
        userAvatar = hub.playerTier.avatarAsset
    }

    var bot: Bot { session.bot }

    func start() { session.start() }

    // MARK: Moves

    /// The board contract: only on the user's turn, with the user's side to move, and only on
    /// the live position (an earlier position is read-only).
    var interactive: Bool {
        viewedPly == nil && session.phase == .userTurn
            && Position(fen: session.fen)?.sideToMove == session.userColor
    }

    /// Called from the board's gesture, inside its animation transaction, so the session's
    /// tracker changes in the same transaction and a dropped piece does not jump back.
    /// The user's own move always lands on the live board.
    func move(_ uci: String) -> Bool {
        hintUnavailable = false
        let played = session.userMove(uci)
        if played { returnToLive() }
        return played
    }

    // MARK: Viewing history

    /// The ply whose position the board shows while the user looks back (0 = the start);
    /// nil = live. Never the last ply: that is the live position. A take-back that removes
    /// the viewed ply ends viewing.
    var viewedPly: Int? {
        guard let ply = storedViewedPly, ply < session.moves.count else { return nil }
        return ply
    }

    private var storedViewedPly: Int?
    /// Moves in the game when viewing started; more now means the bot moved meanwhile.
    private var movesWhenViewingStarted = 0

    /// The bot moved while the user was looking back ("Back to live" shows a dot).
    var hasNewMovesWhileViewing: Bool {
        viewedPly != nil && session.moves.count > movesWhenViewingStarted
    }

    /// Shows the position after `ply` (0 = start), read-only. The last ply or nil is live.
    func select(ply: Int?) {
        guard let ply, ply < session.moves.count else {
            returnToLive()
            return
        }
        if viewedPly == nil { movesWhenViewingStarted = session.moves.count }
        storedViewedPly = max(0, ply)
    }

    /// ‹ / ›: one ply back or forward from what the board shows; past the end is live.
    func step(_ delta: Int) {
        select(ply: max(0, displayedPly + delta))
    }

    func returnToLive() {
        storedViewedPly = nil
    }

    /// The ply the board shows (the live position is `moves.count`).
    var displayedPly: Int { viewedPly ?? session.moves.count }

    var canStepBack: Bool { displayedPly > 0 }
    var canStepForward: Bool { viewedPly != nil }

    var displayedFen: String { viewedPly.map { history(at: $0).fen } ?? session.fen }

    var displayedTracker: PieceTracker { viewedPly.map { history(at: $0).tracker } ?? session.tracker }

    var displayedLastMove: (from: Square, to: Square)? {
        guard let ply = viewedPly else { return session.lastMove }
        guard ply > 0 else { return nil }
        let uci = session.moves[ply - 1]
        return (Square(String(uci.prefix(2))), Square(String(uci.dropFirst(2).prefix(2))))
    }

    /// The last earlier position built, replayed from the start so piece ids match the live
    /// tracker (stepping animates the same piece views).
    @ObservationIgnored private var historyCache: (moves: ArraySlice<String>, fen: String, tracker: PieceTracker)?

    private func history(at ply: Int) -> (fen: String, tracker: PieceTracker) {
        let prefix = session.moves.prefix(ply)
        if let cached = historyCache, cached.moves == prefix { return (cached.fen, cached.tracker) }
        var fen = session.startFen
        var tracker = PieceTracker(fen: fen)
        for uci in prefix {
            guard let applied = Rules.apply(uci: uci, to: fen) else { break }
            tracker.apply(uci, fenBefore: fen)
            fen = applied.fenAfter
        }
        historyCache = (prefix, fen, tracker)
        return (fen, tracker)
    }

    // MARK: Move strip and status

    /// Grades are coaching: Silent shows them only once the game is over.
    private var showsGrades: Bool { session.mode == .training || isOver }

    var stripItems: [MoveStripItem] {
        session.sans.enumerated().map { index, san in
            let ply = index + 1
            let verdict = showsGrades ? session.verdicts[ply] : nil
            return MoveStripItem(ply: ply, san: san, moveClass: verdict?.classification)
        }
    }

    /// The status line: the opening's name through move 12, then what is happening (the bot
    /// thinking, the move being checked) or the last grade, "Nf3 · Best ★". Viewing history
    /// shows the viewed move's grade.
    var statusText: String? {
        if hintUnavailable { return "Hint unavailable" }
        if isOver { return endReason }
        if let ply = viewedPly {
            return ply > 0 ? verdictText(ply) : "Start position"
        }
        if session.moves.count < Self.openingPlies, let opening = openingName { return opening }
        switch session.phase {
        case .botThinking: return "\(bot.name) is thinking…"
        case .grading: return "Checking your move…"
        default:
            let last = session.verdicts.keys.max()
            return last.flatMap(verdictText)
        }
    }

    /// Move 12 is ply 23 / 24.
    static let openingPlies = 24

    private func verdictText(_ ply: Int) -> String? {
        guard showsGrades, let verdict = session.verdicts[ply] else { return nil }
        return "\(verdict.san) · \(verdict.classification.label) \(verdict.classification.glyph)"
    }

    @ObservationIgnored private var openingCache: (moves: [String], name: String?)?

    private var openingName: String? {
        let moves = session.moves
        if let cached = openingCache, cached.moves == moves { return cached.name }
        let name = OpeningBook.deepest(startFen: session.startFen, moves: moves)?.name
        openingCache = (moves, name)
        return name
    }

    // MARK: Player bars

    var opponentBar: PlayerBarModel {
        let color = session.userColor.opposite
        return PlayerBarModel(name: bot.name, elo: bot.elo, avatarAsset: bot.avatarAsset,
                              captured: captured(by: color).map(BoardMaterial.code), materialLead: materialLead(for: color))
    }

    var userBar: PlayerBarModel {
        let color = session.userColor
        return PlayerBarModel(name: "You", elo: nil, avatarAsset: userAvatar,
                              captured: captured(by: color).map(BoardMaterial.code), materialLead: materialLead(for: color))
    }

    /// Shows the engine's best move. "Hint unavailable" only when the hint failed for the
    /// position it was asked about; a hint overtaken by a move (or take-back) is just dropped.
    func hint() async {
        hintUnavailable = false
        isHinting = true
        let askedAt = session.moves
        let shown = await session.hint()
        isHinting = false
        hintUnavailable = !shown && session.moves == askedAt
    }

    func flip() { orientation = orientation.opposite }

    // MARK: Board decorations

    var interruption: Verdict? {
        if case .interrupted(let verdict) = session.phase { return verdict }
        return nil
    }

    /// The verdict marked on the board: the interrupting one live, the viewed ply's grade
    /// (when grades may be shown) in history.
    private var markedVerdict: Verdict? {
        if let ply = viewedPly {
            return showsGrades && ply > 0 ? session.verdicts[ply] : nil
        }
        return interruption
    }

    private var markedSquare: Square? {
        markedVerdict.map { Square(String($0.uci.dropFirst(2).prefix(2))) }
    }

    var squareTint: [Square: Color] {
        guard let verdict = markedVerdict, let square = markedSquare else { return [:] }
        return [square: DS.Color.moveClass(verdict.classification)]
    }

    var badges: [Square: MoveClass] {
        guard let verdict = markedVerdict, let square = markedSquare else { return [:] }
        return [square: verdict.classification]
    }

    var arrows: [(Square, Square, Color)] {
        guard viewedPly == nil else { return [] }
        return session.bestArrow.map { [($0.from, $0.to, DS.Color.accent)] } ?? []
    }

    /// White-relative eval after the latest graded move up to the shown ply; even until the
    /// first grade.
    var whiteCp: Double {
        let shown = displayedPly
        return Double(session.verdicts.filter { $0.key <= shown }.max { $0.key < $1.key }?.value.evalWhiteCp ?? 0)
    }

    // MARK: Captured material

    /// Pieces `color` has taken in the shown position, cheapest first.
    func captured(by color: Piece.Color) -> [Piece] {
        BoardMaterial.captured(by: color, fen: displayedFen)
    }

    /// Material `color` is ahead by in the shown position, in pawns (0 when level or behind).
    func materialLead(for color: Piece.Color) -> Int {
        BoardMaterial.lead(for: color, fen: displayedFen)
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

    // MARK: Game-over summary

    /// Both sides' analysis of the finished game (`GameAnalyzer` at the Review depth), run while
    /// the result panel is up: the bot's accuracy and move classes, the key moment. Saved with
    /// the game, so Review opens without analysing again.
    private(set) var summaryAnalysis: GameAnalysis?
    /// 0…1 while the summary analysis runs; nil otherwise.
    private(set) var summaryProgress: Double?
    @ObservationIgnored private var summaryTask: Task<GameAnalysis, any Error>?

    /// Analyses the finished game once its live grades are in (the engine is free then).
    /// Returns when the run ends; a cancelled or failed run leaves `summaryAnalysis` nil
    /// (Review analyses the game later).
    func analyzeFinishedGame(engine: any ChessEngine) async {
        guard isOver, summaryAnalysis == nil, summaryTask == nil, !session.moves.isEmpty else { return }
        _ = await session.finalSnapshot()
        guard !Task.isCancelled, !isSaved, summaryTask == nil else { return }
        let analyzer = GameAnalyzer(engine: engine, depth: ReviewModel.depth)
        let startFen = session.startFen
        let moves = session.moves
        summaryProgress = 0
        let task = Task {
            try await analyzer.analyze(startFen: startFen, moves: moves) { [weak self] done, total in
                Task { @MainActor in
                    guard let self, self.summaryTask != nil else { return }
                    self.summaryProgress = Double(done) / Double(max(total, 1))
                }
            }
        }
        summaryTask = task
        let outcome = await withTaskCancellationHandler { await task.result } onCancel: { task.cancel() }
        guard summaryTask != nil else { return }  // cancelled meanwhile
        summaryTask = nil
        summaryProgress = nil
        if case .success(let analysis) = outcome, analysis.verdicts.count == moves.count {
            summaryAnalysis = analysis
        }
    }

    /// Stops the summary analysis (leaving for a rematch or another bot).
    func cancelSummaryAnalysis() {
        summaryTask?.cancel()
        summaryTask = nil
        summaryProgress = nil
    }

    /// Waits for a running summary analysis to finish (Review needs it anyway).
    func waitForSummary() async {
        if let summaryTask { _ = await summaryTask.result }
    }

    private var analysedVerdicts: [Verdict]? { summaryAnalysis?.verdicts }

    /// A side's accuracy on the panel: the analysis once it is in; for the user, the live
    /// grades until then (the bot's moves are not graded live).
    func summaryAccuracy(for color: Piece.Color) -> Double? {
        if let analysis = summaryAnalysis {
            return color == .white ? analysis.accuracyWhite : analysis.accuracyBlack
        }
        return color == session.userColor ? accuracy : nil
    }

    /// A side's move classes with counts (only classes that occur, best first).
    func summaryCounts(for color: Piece.Color) -> [(moveClass: MoveClass, count: Int)] {
        let verdicts = analysedVerdicts ?? (color == session.userColor ? userVerdicts : [])
        return moveClassCounts(verdicts.filter { $0.mover == color })
    }

    /// The move that swung the game most (either side once analysed, the user's before).
    var summaryKeyMoment: Verdict? {
        keyMoment(analysedVerdicts ?? userVerdicts)
    }

    /// The position after `ply` (0 = the start).
    func fen(afterPly ply: Int) -> String {
        var fen = session.startFen
        for uci in session.moves.prefix(ply) {
            guard let applied = Rules.apply(uci: uci, to: fen) else { break }
            fen = applied.fenAfter
        }
        return fen
    }

    // MARK: Saving

    /// Stores the game once, after its last grades are in (`finalSnapshot`, never `snapshot()`),
    /// with the summary analysis when it finished.
    /// A grade halted by an engine error is retried up to `maxGradeRetries` times; after that the
    /// partial game is stored (Plan 2 re-analyses it). A failed write leaves the game unsaved,
    /// so the next Done / Play again tries again.
    func save(in context: ModelContext) async throws {
        guard !isSaved, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        var snapshot = await session.finalSnapshot()
        var retries = 0
        while session.hasEngineError, session.pendingGradeCount > 0, retries < Self.maxGradeRetries {
            retries += 1
            session.retry()
            snapshot = await session.finalSnapshot()
        }
        if let analysis = summaryAnalysis, analysis.verdicts.count == snapshot.moves.count {
            snapshot.analysis = analysis
            snapshot.openingName = OpeningBook.deepest(startFen: snapshot.startFen, moves: snapshot.moves)?.name
        }
        try persist(snapshot, context)
        savedGameID = snapshot.id
        isSaved = true
    }

    static let maxGradeRetries = 2

    /// Inserts and saves the record; a failed save removes the insert so a retry stores one copy.
    static func insertRecord(_ snapshot: GameSnapshot, into context: ModelContext) throws {
        let record = try GameRecord(snapshot: snapshot)
        context.insert(record)
        do {
            try context.save()
        } catch {
            context.delete(record)
            throw error
        }
    }
}
