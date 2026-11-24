import SwiftUI
import SwiftData
import OSLog
import Observation
import ChessCore

/// The analysis board: the user moves both colours from any position. Every move is graded
/// live and in order (`LineGrader`, depth 14, as in Review); the shown position is searched for
/// the eval bar and the best-move arrow (depth 14, or 20 with Deep). The line autosaves as an
/// owner-less `GameRecord` (`source: freeplay`), which the rating, Profile, the ladder and
/// Home's recent games leave out.
///
/// Playing a move at an earlier position replaces the rest of the line (no variations).
@MainActor @Observable
final class FreeplayModel {
    static let depth = 14
    static let deepDepth = 20

    private(set) var startFen: String
    private(set) var moves: [String] = []
    private(set) var sans: [String] = []
    /// The position shown: the ply played last (0 = the start position).
    private(set) var selectedPly = 0
    var orientation: Piece.Color = .white
    /// The best-move arrow, kept on from move to move (an analysis-board mode).
    var showsBest = false
    /// Deeper search (depth 20) for the eval bar and the best move.
    var deep = false {
        didSet { if deep != oldValue { refreshEval() } }
    }

    /// The search of the shown position, once it lands.
    private(set) var positionEval: AnalysisResult?
    private(set) var evalFailed = false

    private(set) var grader: LineGrader
    @ObservationIgnored private let engine: any ChessEngine
    @ObservationIgnored private var record: GameRecord?
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var evalTask: Task<Void, Never>?
    @ObservationIgnored private var evalKey: String?
    @ObservationIgnored private var recordID = UUID()
    @ObservationIgnored private var date = Date.now

    private static let log = Logger(subsystem: "uz.xq.chessc", category: "freeplay")

    /// - Parameters:
    ///   - record: a saved analysis-board line to continue, or nil for a fresh board.
    ///   - startFen: the position of a fresh board (the editor's).
    init(engine: any ChessEngine, record: GameRecord? = nil, startFen: String = Rules.startFen,
         context: ModelContext? = nil) {
        self.engine = engine
        self.context = context
        if let record, let snapshot = record.snapshot, snapshot.isFreeplay {
            self.record = record
            recordID = record.id
            date = snapshot.date
            self.startFen = snapshot.startFen
            grader = LineGrader(engine: engine, startFen: snapshot.startFen, depth: Self.depth)
            var fen = snapshot.startFen
            for uci in snapshot.moves {
                guard let applied = Rules.apply(uci: uci, to: fen) else { break }
                moves.append(uci)
                sans.append(applied.san)
                fen = applied.fenAfter
            }
            grader.restore(snapshot.verdicts.filter { moves.indices.contains($0.ply - 1) && $0.uci == moves[$0.ply - 1] })
            // Plies saved before their grade landed are graded again.
            for index in moves.indices where grader.verdicts[index + 1] == nil {
                grader.enqueue(history: Array(moves.prefix(index)), uci: moves[index])
            }
            selectedPly = moves.count
        } else {
            self.startFen = startFen
            grader = LineGrader(engine: engine, startFen: startFen, depth: Self.depth)
        }
        orientation = Self.sideToMove(fen: self.startFen) == .black && moves.isEmpty ? .black : .white
    }

    // MARK: Positions

    var displayedFen: String { position(after: selectedPly).fen }
    var displayedTracker: PieceTracker { position(after: selectedPly).tracker }

    @ObservationIgnored private var positionCache: (moves: [String], fen: String, tracker: PieceTracker)?

    private func position(after ply: Int) -> (fen: String, tracker: PieceTracker) {
        let prefix = Array(moves.prefix(ply))
        if let cached = positionCache, cached.moves == prefix { return (cached.fen, cached.tracker) }
        var fen = startFen
        var tracker = PieceTracker(fen: fen)
        for uci in prefix {
            guard let applied = Rules.apply(uci: uci, to: fen) else { break }
            tracker.apply(uci, fenBefore: fen)
            fen = applied.fenAfter
        }
        positionCache = (prefix, fen, tracker)
        return (fen, tracker)
    }

    var displayedLastMove: (from: Square, to: Square)? {
        guard selectedPly > 0 else { return nil }
        return Self.squares(moves[selectedPly - 1])
    }

    var state: GameState {
        Rules.state(fen: displayedFen, history: Array(moves.prefix(selectedPly)), startFen: startFen)
    }

    var isOver: Bool {
        switch state {
        case .active, .check: false
        default: true
        }
    }

    /// Either side may move, unless the shown position is over.
    var interactive: Bool { !isOver }

    // MARK: Moves

    /// A move on the board at the shown position. The line's own next move just steps forward;
    /// anything else replaces the rest of the line. Returns false if illegal.
    @discardableResult
    func play(_ uci: String) -> Bool {
        guard let applied = Rules.apply(uci: uci, to: displayedFen) else { return false }
        if selectedPly < moves.count, moves[selectedPly] == uci {
            select(ply: selectedPly + 1)
            return true
        }
        if selectedPly < moves.count {
            moves.removeLast(moves.count - selectedPly)
            sans.removeLast(sans.count - selectedPly)
            grader.discard(after: selectedPly)
        }
        grader.enqueue(history: moves, uci: uci)
        moves.append(uci)
        sans.append(applied.san)
        selectedPly = moves.count
        refreshEval()
        save()
        return true
    }

    /// Takes back the line's last move and shows the position before it.
    func takeBack() {
        guard !moves.isEmpty else { return }
        moves.removeLast()
        sans.removeLast()
        grader.discard(after: moves.count)
        selectedPly = min(selectedPly, moves.count)
        refreshEval()
        save()
    }

    var canTakeBack: Bool { !moves.isEmpty }

    func select(ply: Int) {
        let clamped = min(max(0, ply), moves.count)
        guard clamped != selectedPly else { return }
        selectedPly = clamped
        refreshEval()
    }

    func step(_ delta: Int) { select(ply: selectedPly + delta) }
    var canStepBack: Bool { selectedPly > 0 }
    var canStepForward: Bool { selectedPly < moves.count }

    func flip() { orientation = orientation.opposite }

    /// A new board from `fen` (the editor's position, or the start position): a new saved line.
    func reset(to fen: String) {
        evalTask?.cancel()
        grader.reset()
        startFen = fen
        grader = LineGrader(engine: engine, startFen: fen, depth: Self.depth)
        moves = []
        sans = []
        selectedPly = 0
        showsBest = false
        positionEval = nil
        evalKey = nil
        record = nil
        recordID = UUID()
        date = .now
        orientation = Self.sideToMove(fen: fen)
        refreshEval()
    }

    // MARK: Engine

    var depth: Int { deep ? Self.deepDepth : Self.depth }

    /// Searches the shown position (once per position and depth), for the eval bar and the
    /// best move. A newer position cancels the older search.
    func refreshEval() {
        let history = Array(moves.prefix(selectedPly))
        let key = "\(depth)|\(startFen)|\(history.joined(separator: " "))"
        guard key != evalKey || evalFailed else { return }
        evalKey = key
        evalFailed = false
        evalTask?.cancel()
        guard !isOver else { positionEval = nil; return }
        let request = AnalysisRequest(startFen: startFen, moves: history, depth: depth, multiPV: 2)
        let engine = engine
        evalTask = Task { [weak self] in
            do {
                let result = try await engine.analyze(request)
                guard !Task.isCancelled, let self, self.evalKey == key else { return }
                self.positionEval = result
                if let score = result.lines.first?.score {
                    self.lastWhiteCp = toCp(score, sideToMove: Self.sideToMove(fen: self.displayedFen))
                }
            } catch is CancellationError {
            } catch {
                guard let self, self.evalKey == key else { return }
                Self.log.error("Freeplay eval failed: \(String(describing: error), privacy: .public)")
                self.evalFailed = true
            }
        }
    }

    /// The eval of the shown position belongs to it (not to an older position still on screen).
    private var currentEval: AnalysisResult? {
        let history = Array(moves.prefix(selectedPly))
        let key = "\(depth)|\(startFen)|\(history.joined(separator: " "))"
        return evalKey == key ? positionEval : nil
    }

    /// Stops the searches (leaving the screen).
    func cancel() {
        evalTask?.cancel()
        evalTask = nil
    }

    /// White-relative centipawns of the shown position: its own search, else the grade of the
    /// move that led to it, else level.
    var whiteCp: Double {
        if case .checkmate(let winner) = state { return winner == .white ? 10000 : -10000 }
        if isOver { return 0 }
        if let score = currentEval?.lines.first?.score {
            return toCp(score, sideToMove: Self.sideToMove(fen: displayedFen))
        }
        if let verdict = selectedVerdict { return Double(verdict.evalWhiteCp) }
        return lastWhiteCp
    }

    /// The last landed eval, so the bar does not jump back to level while the next search runs.
    private var lastWhiteCp: Double = 0

    /// The engine's best move in the shown position.
    var bestMove: (from: Square, to: Square)? {
        guard let best = currentEval?.bestMove, !best.isEmpty else { return nil }
        return Self.squares(best)
    }

    var bestSan: String? {
        guard let best = currentEval?.bestMove, !best.isEmpty else { return nil }
        return Rules.apply(uci: best, to: displayedFen)?.san
    }

    var canShowBest: Bool { bestMove != nil }

    var arrows: [(Square, Square, Color)] {
        guard showsBest, let best = bestMove else { return [] }
        return [(best.from, best.to, DS.Color.accent)]
    }

    // MARK: Grades

    func verdict(atPly ply: Int) -> Verdict? { ply > 0 ? grader.verdicts[ply] : nil }

    var selectedVerdict: Verdict? { verdict(atPly: selectedPly) }

    private var markedSquare: Square? {
        selectedVerdict.map { Square(String($0.uci.dropFirst(2).prefix(2))) }
    }

    var squareTint: [Square: Color] {
        guard let verdict = selectedVerdict, let square = markedSquare else { return [:] }
        return [square: DS.Color.moveClass(verdict.classification)]
    }

    var badges: [Square: MoveClass] {
        guard let verdict = selectedVerdict, let square = markedSquare else { return [:] }
        return [square: verdict.classification]
    }

    var stripItems: [MoveStripItem] {
        sans.enumerated().map { index, san in
            MoveStripItem(ply: index + 1, san: san, moveClass: grader.verdicts[index + 1]?.classification)
        }
    }

    // MARK: Text

    var openingName: String? { OpeningBook.deepest(startFen: startFen, moves: Array(moves.prefix(selectedPly)))?.name }

    /// The navigation subtitle: the opening, else what kind of board this is.
    var subtitle: String {
        if let openingName { return openingName }
        return startFen == Rules.startFen ? "Start position" : "Your position"
    }

    /// The status line: the result, the shown move's grade, "Checking …", or whose move it is.
    var statusText: String {
        switch state {
        case .checkmate(let winner): return "Checkmate · \(winner == .white ? "White" : "Black") wins"
        case .stalemate: return "Stalemate · draw"
        case .insufficientMaterial: return "Draw · not enough material"
        case .threefold: return "Draw · threefold repetition"
        case .fiftyMove: return "Draw · fifty-move rule"
        case .active, .check: break
        }
        if grader.hasError { return "Analysis stopped" }
        if selectedPly > 0 {
            let san = sans[selectedPly - 1]
            guard let verdict = selectedVerdict else { return "Checking \(san)…" }
            let base = "\(verdict.san) · \(verdict.classification.label) \(verdict.classification.glyph)"
            if verdict.classification.isNegative, !verdict.bestSan.isEmpty, verdict.bestSan != verdict.san {
                return base + " · best \(verdict.bestSan)"
            }
            return base
        }
        return "\(Self.sideToMove(fen: displayedFen) == .white ? "White" : "Black") to move"
    }

    // MARK: Bars

    func bar(for color: Piece.Color) -> PlayerBarModel {
        let tray = BoardMaterial.tray(for: color, fen: displayedFen)
        return PlayerBarModel(name: color == .white ? "White" : "Black", elo: nil,
                              avatarAsset: color == .white ? "Pieces/wk" : "Pieces/bk",
                              captured: tray.captured, materialLead: tray.lead)
    }

    // MARK: Saving

    func attach(_ context: ModelContext) {
        if self.context == nil { self.context = context }
    }

    /// The line as a saved game: owner-less (White as the nominal user colour), never rated.
    var snapshot: GameSnapshot {
        let result: GameResult
        switch Rules.state(fen: Rules.fen(startFen: startFen, moves: moves) ?? startFen, history: moves, startFen: startFen) {
        case .checkmate(let winner): result = winner == .white ? .whiteWins : .blackWins
        case .stalemate, .insufficientMaterial, .threefold, .fiftyMove: result = .draw
        case .active, .check: result = .ongoing
        }
        return GameSnapshot(
            id: recordID, date: date, botId: "", userColor: .white, mode: .silent, startFen: startFen,
            moves: moves, sans: sans, result: result,
            verdicts: grader.verdicts.values.sorted { $0.ply < $1.ply },
            analysisVersion: 1, playerRatingUsed: PlayerProfile.defaultRating,
            openingName: OpeningBook.deepest(startFen: startFen, moves: moves)?.name,
            source: GameSnapshot.Source.freeplay)
    }

    /// Writes the line (and the grades that have landed) to its record; an empty fresh board
    /// is not saved.
    func save() {
        guard let context else { return }
        if record == nil && moves.isEmpty { return }
        do {
            if let record {
                try record.update(snapshot)
            } else {
                let new = try GameRecord(snapshot: snapshot)
                context.insert(new)
                record = new
            }
            context.saveReporting("the analysis board")
        } catch {
            Self.log.error("Saving the analysis board failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Helpers

    static func sideToMove(fen: String) -> Piece.Color {
        fen.split(separator: " ").dropFirst().first == "b" ? .black : .white
    }

    private static func squares(_ uci: String) -> (from: Square, to: Square)? {
        guard uci.count >= 4 else { return nil }
        return (Square(String(uci.prefix(2))), Square(String(uci.dropFirst(2).prefix(2))))
    }
}
