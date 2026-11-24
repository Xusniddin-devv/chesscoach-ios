import SwiftUI
import SwiftData
import OSLog
import Observation
import ChessCore

/// A move of a line the user tries on the Review board. `ply` counts from the game's start,
/// like the game's own plies, so a branch at ply 10 starts with ply 11.
struct BranchMove: Equatable {
    let ply: Int
    let uci: String
    let san: String
}

/// One saved game under review: the full-game analysis (run once, stored in the record),
/// stepping through the game, and branches tried on the board, graded live and never saved.
///
/// Analysis runs only when the stored one is missing or older than `GameAnalysis.currentVersion`;
/// a finished run is written into the record (`analysis`, `openingName`) and makes the next
/// visit instant. Leaving cancels it and nothing partial is stored. Bulk analysis never runs
/// while a game is being played (`analysisAllowed`): then Review shows what is saved.
@MainActor @Observable
final class ReviewModel {
    /// Bulk review depth (global constraints); branch grades use it too, so a branch's first
    /// "before" is the analysed game position, already in the engine's cache.
    static let depth = 14

    let record: GameRecord
    private(set) var snapshot: GameSnapshot
    /// False when the record's game is unreadable: nothing to show or analyse.
    let isReadable: Bool
    let analysisAllowed: Bool
    let wording: MoveWording

    /// 0…1 while the game is being analysed; nil otherwise.
    private(set) var analysisProgress: Double?
    /// Positions analysed so far and in all, for "Analysing 12 / 48".
    private(set) var analysedPositions = 0
    private(set) var totalPositions = 0
    private(set) var analysis: GameAnalysis?
    /// The last run stopped on an engine error; `start()` again retries.
    private(set) var analysisFailed = false

    /// The position shown: the ply played last (0 = the start), counted along the current
    /// line (the game, or the game up to `branchBase` and then the branch).
    private(set) var selectedPly = 0
    /// The line tried on the board, or nil when the game itself is shown.
    private(set) var branch: [BranchMove]?
    /// The game ply the branch starts after.
    private(set) var branchBase = 0
    var orientation: Piece.Color
    /// The user's avatar in the bar (their tier's piece).
    var userAvatar = RatingTier.pawn.avatarAsset
    /// The best-move arrow for a negative move.
    var showsBest = false

    @ObservationIgnored let grader: LineGrader
    @ObservationIgnored private let engine: any ChessEngine
    @ObservationIgnored private var analysisTask: Task<GameAnalysis, any Error>?
    /// Bumped by `cancel()`; a run from an older generation stores nothing.
    @ObservationIgnored private var run = 0

    private static let log = Logger(subsystem: "uz.xq.chessc", category: "review")

    init(record: GameRecord, engine: any ChessEngine, analysisAllowed: Bool = true, wording: MoveWording = .words) {
        self.record = record
        self.engine = engine
        self.analysisAllowed = analysisAllowed
        self.wording = wording
        let decoded = record.snapshot
        isReadable = decoded != nil
        let snapshot = decoded ?? GameSnapshot(
            id: record.id, date: record.date, botId: "", userColor: .white, mode: .silent,
            startFen: Rules.startFen, moves: [], sans: [], result: .ongoing, verdicts: [],
            analysisVersion: 1, playerRatingUsed: PlayerProfile.defaultRating)
        self.snapshot = snapshot
        orientation = snapshot.userColor
        // A quick pass (onboarding) or a Lichess-evals analysis is upgraded: Review re-analyses
        // at full depth on open and stores that.
        if let stored = snapshot.analysis, stored.version == GameAnalysis.currentVersion,
           stored.verdicts.count == snapshot.moves.count, stored.isFull {
            analysis = stored
        }
        grader = LineGrader(engine: engine, startFen: snapshot.startFen, depth: Self.depth)
    }

    var bot: Bot? { Bot.all.first { $0.id == snapshot.botId } }
    var botName: String { bot?.name ?? snapshot.botId }
    var needsAnalysis: Bool { isReadable && analysis == nil }
    var isAnalysing: Bool { analysisProgress != nil }

    // MARK: Analysis

    /// Analyses the game if it has no current analysis, then stores it in the record. Returns
    /// when the run ends: done, failed (`analysisFailed`), or cancelled (by the caller's task
    /// or `cancel()`), in which case nothing is stored.
    func start() async {
        guard needsAnalysis, analysisAllowed, analysisTask == nil else { return }
        run += 1
        let thisRun = run
        analysisFailed = false
        analysedPositions = 0
        totalPositions = snapshot.moves.count + 1
        analysisProgress = 0

        let analyzer = GameAnalyzer(engine: engine, depth: Self.depth)
        let startFen = snapshot.startFen
        let moves = snapshot.moves
        let task = Task {
            try await analyzer.analyze(startFen: startFen, moves: moves) { [weak self] done, total in
                Task { @MainActor in self?.progressed(done, of: total, run: thisRun) }
            }
        }
        analysisTask = task
        let outcome = await withTaskCancellationHandler {
            await task.result
        } onCancel: {
            task.cancel()
        }
        guard thisRun == run else { return }  // cancelled meanwhile: `cancel()` reset the state
        analysisTask = nil
        analysisProgress = nil
        switch outcome {
        case .success(let result) where !Task.isCancelled:
            store(result)
        case .success:
            break
        case .failure(let error):
            if !(error is CancellationError) {
                Self.log.error("Review analysis failed: \(String(describing: error), privacy: .public)")
                analysisFailed = true
            }
        }
    }

    private func progressed(_ done: Int, of total: Int, run thisRun: Int) {
        guard thisRun == run, analysisTask != nil else { return }
        analysedPositions = done
        totalPositions = total
        analysisProgress = Double(done) / Double(max(total, 1))
    }

    private func store(_ result: GameAnalysis) {
        analysis = result
        var updated = snapshot
        updated.analysis = result
        updated.openingName = OpeningBook.deepest(startFen: snapshot.startFen, moves: snapshot.moves)?.name
        snapshot = updated
        do {
            try record.update(updated)
            try record.modelContext?.save()
        } catch {
            // The analysis stays on screen; the next visit runs it again.
            Self.log.error("Storing the analysis failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Leaving Review: stops the analysis (nothing partial is stored) and drops branch grades.
    func cancel() {
        run += 1
        analysisTask?.cancel()
        analysisTask = nil
        analysisProgress = nil
        grader.reset()
    }

    // MARK: Lines and positions

    /// The game's moves (UCI).
    var gameMoves: [String] { snapshot.moves }

    /// The moves of the line shown: the game, or its first `branchBase` moves and the branch.
    var currentLine: [String] {
        guard let branch else { return snapshot.moves }
        return Array(snapshot.moves.prefix(branchBase)) + branch.map(\.uci)
    }

    var isInBranch: Bool { branch != nil }

    /// Shows the position after `ply` of the current line (clamped to it).
    func select(ply: Int) {
        selectedPly = min(max(0, ply), currentLine.count)
    }

    /// ‹ / ›: one ply back or forward.
    func step(_ delta: Int) {
        select(ply: selectedPly + delta)
    }

    var canStepBack: Bool { selectedPly > 0 }
    var canStepForward: Bool { selectedPly < currentLine.count }

    /// Branches need the engine to themselves: only once the game is analysed.
    var interactive: Bool { isReadable && analysis != nil && !isAnalysing && analysisAllowed }

    /// A move played on the board at the shown position. The line's own next move just steps
    /// forward; anything else starts a branch here (or, inside a branch, replaces the rest of
    /// it) and is graded with the history that leads to it. Returns false if not accepted.
    @discardableResult
    func playBranchMove(_ uci: String) -> Bool {
        guard interactive, let applied = Rules.apply(uci: uci, to: displayedFen) else { return false }
        let line = currentLine
        if selectedPly < line.count, line[selectedPly] == uci {
            selectedPly += 1
            return true
        }
        if let current = branch, selectedPly >= branchBase {
            if current.count > selectedPly - branchBase {
                branch = Array(current.prefix(selectedPly - branchBase))
                grader.discard(after: selectedPly)
            }
        } else {
            grader.reset()
            branchBase = selectedPly
            branch = []
        }
        let history = Array(line.prefix(selectedPly))
        branch!.append(BranchMove(ply: selectedPly + 1, uci: uci, san: applied.san))
        grader.enqueue(history: history, uci: uci)
        selectedPly += 1
        showsBest = false
        return true
    }

    /// "Back to game": drops the branch (late grades included) and shows where it started.
    func exitBranch() {
        guard branch != nil else { return }
        grader.reset()
        branch = nil
        selectedPly = min(branchBase, snapshot.moves.count)
    }

    var displayedFen: String { position(after: selectedPly).fen }
    var displayedTracker: PieceTracker { position(after: selectedPly).tracker }

    var displayedLastMove: (from: Square, to: Square)? {
        guard selectedPly > 0, let uci = currentLine[safe: selectedPly - 1] else { return nil }
        return Self.squares(uci)
    }

    /// Replayed from the start so piece ids stay the same between plies (stepping animates).
    @ObservationIgnored private var positionCache: (moves: [String], fen: String, tracker: PieceTracker)?

    private func position(after ply: Int) -> (fen: String, tracker: PieceTracker) {
        let prefix = Array(currentLine.prefix(ply))
        if let cached = positionCache, cached.moves == prefix { return (cached.fen, cached.tracker) }
        var fen = snapshot.startFen
        var tracker = PieceTracker(fen: fen)
        for uci in prefix {
            guard let applied = Rules.apply(uci: uci, to: fen) else { break }
            tracker.apply(uci, fenBefore: fen)
            fen = applied.fenAfter
        }
        positionCache = (prefix, fen, tracker)
        return (fen, tracker)
    }

    // MARK: Verdicts

    private func isBranchPly(_ ply: Int) -> Bool { branch != nil && ply > branchBase }

    /// The grade of `ply` on the current line: the analysis for the game's plies, the live
    /// grade for a branch's.
    func verdict(atPly ply: Int) -> Verdict? {
        guard ply > 0 else { return nil }
        if isBranchPly(ply) { return grader.verdicts[ply] }
        return gameVerdict(atPly: ply)
    }

    /// The analysis' grade of the game's own ply.
    func gameVerdict(atPly ply: Int) -> Verdict? {
        if let verdict = analysis?.verdicts[safe: ply - 1], verdict.ply == ply { return verdict }
        return analysis?.verdicts.first { $0.ply == ply }
    }

    var selectedVerdict: Verdict? { verdict(atPly: selectedPly) }

    /// The selected move is a branch move whose grade has not arrived.
    var isCheckingSelected: Bool {
        isBranchPly(selectedPly) && grader.verdicts[selectedPly] == nil && !grader.hasError
    }

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

    /// The best move instead of a negative one can be shown.
    var canShowBest: Bool {
        guard let verdict = selectedVerdict else { return false }
        return verdict.classification.isNegative && Self.squares(verdict.bestMove) != nil
    }

    var arrows: [(Square, Square, Color)] {
        guard showsBest, canShowBest, let verdict = selectedVerdict,
              let best = Self.squares(verdict.bestMove) else { return [] }
        return [(best.from, best.to, DS.Color.accent)]
    }

    /// White-relative eval of the shown position: the analysis on the game's plies, the
    /// latest branch grade inside a branch (the branch's start until the first one arrives).
    var whiteCp: Double {
        if isBranchPly(selectedPly) {
            let graded = grader.verdicts.filter { $0.key > branchBase && $0.key <= selectedPly }
            if let latest = graded.max(by: { $0.key < $1.key }) { return Double(latest.value.evalWhiteCp) }
            return Self.cp(fromWhiteWin: analysis?.whiteWin[safe: branchBase] ?? 50)
        }
        return Self.cp(fromWhiteWin: analysis?.whiteWin[safe: selectedPly] ?? 50)
    }

    /// Inverse of `winPercent` (within its ±1500 cp clamp).
    static func cp(fromWhiteWin win: Double) -> Double {
        let p = min(max(win, 0.01), 99.99) / 100
        return -Foundation.log(1 / p - 1) / 0.00368208
    }

    // MARK: Explanation and status

    private func isUserMove(_ verdict: Verdict) -> Bool {
        isBranchPly(verdict.ply) || verdict.mover == snapshot.userColor
    }

    /// The coach's comment on the selected move, shown in the card above the action bar.
    var explanation: String? {
        guard let verdict = selectedVerdict else { return nil }
        return Self.comment(on: verdict, byUser: isUserMove(verdict), botName: botName, wording: wording)
    }

    /// A negative move of the user's gets the full explanation (`explain`); everything else
    /// one plain sentence, in the user's voice for their moves and the bot's name for its own.
    static func comment(on verdict: Verdict, byUser: Bool, botName: String, wording: MoveWording) -> String {
        let moveClass = verdict.classification
        let san = verdict.san
        let best = verdict.bestSan
        let otherBest = !best.isEmpty && best != san
        if byUser {
            switch moveClass {
            case .inaccuracy, .mistake, .miss, .blunder: return explain(verdict, wording: wording)
            case .brilliant: return "\(san) is brilliant: you give up material, and it works."
            case .great: return "\(san) is great: the only strong move here."
            case .best: return "\(san) is the best move."
            case .excellent: return otherBest ? "\(san) is excellent, almost as strong as \(best)." : "\(san) is excellent."
            case .good: return otherBest ? "\(san) is good. The best move was \(best)." : "\(san) is good."
            case .book: return "\(san) is a book move: standard opening play."
            case .forced: return "\(san) was forced: the only legal move."
            }
        }
        let played = "\(botName) played \(san)"
        switch moveClass {
        case .inaccuracy, .mistake, .miss, .blunder:
            let label = moveClass.label.lowercased()
            let article = label.first.map { "aeiou".contains($0) } == true ? "an" : "a"
            return "\(played), \(article) \(label)." + (otherBest ? " Better was \(best)." : "")
        case .brilliant: return "\(played), a brilliant sacrifice."
        case .great: return "\(played), the only strong move."
        case .best: return "\(played), the best move."
        case .excellent: return "\(played), an excellent move."
        case .good: return "\(played), a good move." + (otherBest ? " Best was \(best)." : "")
        case .book: return "\(played), a book move."
        case .forced: return "\(played), the only legal move."
        }
    }

    var openingName: String? {
        snapshot.openingName ?? OpeningBook.deepest(startFen: snapshot.startFen, moves: snapshot.moves)?.name
    }

    /// The status line under the board.
    var statusText: String {
        if !isReadable { return "This game can't be read." }
        if isAnalysing { return "Analysing \(analysedPositions) / \(totalPositions)" }
        if analysisFailed { return "Analysis stopped" }
        if isBranchPly(selectedPly) && grader.hasError { return "Analysis stopped" }
        if analysis == nil && !analysisAllowed { return "Analysis runs after your game" }
        if selectedPly == 0 { return openingName ?? "Start position" }
        let san = sanAt(ply: selectedPly) ?? ""
        if isCheckingSelected { return "Checking \(san)…" }
        guard let verdict = selectedVerdict else { return san }
        return "\(verdict.san) · \(verdict.classification.label) \(verdict.classification.glyph)"
    }

    private func sanAt(ply: Int) -> String? {
        if isBranchPly(ply) { return branch?.first { $0.ply == ply }?.san }
        return snapshot.sans[safe: ply - 1]
    }

    /// The move strip: the game with every move's class, or inside a branch the game up to
    /// the branch and then the branch's moves.
    var stripItems: [MoveStripItem] {
        let game = snapshot.sans.enumerated().map { index, san in
            MoveStripItem(ply: index + 1, san: san, moveClass: verdict(atPly: index + 1)?.classification)
        }
        guard let branch else { return game }
        return Array(game.prefix(branchBase)) + branch.map {
            MoveStripItem(ply: $0.ply, san: $0.san, moveClass: grader.verdicts[$0.ply]?.classification, isBranch: true)
        }
    }

    // MARK: Player bars

    func accuracy(for color: Piece.Color) -> Double? {
        guard let analysis else { return nil }
        return color == .white ? analysis.accuracyWhite : analysis.accuracyBlack
    }

    var opponentBar: PlayerBarModel {
        let color = snapshot.userColor.opposite
        let tray = BoardMaterial.tray(for: color, fen: displayedFen)
        return PlayerBarModel(name: botName, elo: bot?.elo, avatarAsset: bot?.avatarAsset,
                              captured: tray.captured, materialLead: tray.lead)
    }

    var userBar: PlayerBarModel {
        let color = snapshot.userColor
        let tray = BoardMaterial.tray(for: color, fen: displayedFen)
        return PlayerBarModel(name: "You", elo: nil, avatarAsset: userAvatar,
                              captured: tray.captured, materialLead: tray.lead)
    }

    func flip() { orientation = orientation.opposite }

    private static func squares(_ uci: String) -> (from: Square, to: Square)? {
        guard uci.count >= 4 else { return nil }
        return (Square(String(uci.prefix(2))), Square(String(uci.dropFirst(2).prefix(2))))
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
