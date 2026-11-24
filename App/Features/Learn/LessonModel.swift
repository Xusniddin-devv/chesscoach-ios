import SwiftUI
import SwiftData
import Observation
import OSLog
import ChessCore
import StockfishKit

/// Drives the lesson screen: wraps `LessonPlayer`, plays scripted replies with a short
/// delay, asks the engine for replies in free-play endgames, and records completion.
@MainActor
@Observable
final class LessonModel {
    private(set) var player: LessonPlayer
    private(set) var tracker: PieceTracker
    private(set) var engineFailed = false
    private(set) var engineHint: String?
    private(set) var thinking = false
    /// Set by a wrong scripted move; cleared by the next accepted move.
    private(set) var wrongMove = false

    private var context: ModelContext?
    private var generation = 0
    private static let log = Logger(subsystem: "uz.xq.chessc", category: "learn")

    /// Full strength for endgame defence and attack (the web used its 2300 level).
    static let engineElo = 3000
    static let autoDelay = Duration.milliseconds(450)

    init(lesson: Lesson) {
        player = LessonPlayer(lesson: lesson)
        tracker = PieceTracker(fen: lesson.startFen)
    }

    func attach(_ context: ModelContext) { self.context = context }

    var lesson: Lesson { player.lesson }
    var interactive: Bool { player.status == .userTurn }

    var lastMove: (Square, Square)? { player.lastMove.map(Self.squares) }

    var squareTint: [Square: Color] {
        guard player.hintLevel >= 1, let move = player.expectedMove else { return [:] }
        return [Self.squares(move).0: DS.Color.accent]
    }

    var arrows: [(Square, Square, Color)] {
        if player.hintLevel >= 2, let move = player.expectedMove {
            let (from, to) = Self.squares(move)
            return [(from, to, DS.Color.accent)]
        }
        if let engineHint, player.status == .userTurn {
            let (from, to) = Self.squares(engineHint)
            return [(from, to, DS.Color.accent)]
        }
        return []
    }

    // MARK: Flow

    func start() { advance() }

    func move(_ uci: String) -> Bool {
        let before = player.fen
        switch player.submit(uci) {
        case .illegal:
            return false
        case .wrong:
            wrongMove = true
            return false
        case .accepted:
            wrongMove = false
            engineHint = nil
            tracker.apply(uci, fenBefore: before)
            advance()
            return true
        }
    }

    func hint() {
        if player.isScripted {
            player.hint()
        } else {
            Task { await engineHintMove() }
        }
    }

    func restart() {
        generation += 1
        player.restart()
        tracker = PieceTracker(fen: lesson.startFen)
        wrongMove = false
        engineHint = nil
        engineFailed = false
        thinking = false
        advance()
    }

    func retryEngine() {
        engineFailed = false
        advance()
    }

    // MARK: Private

    /// Plays whatever is due after the user's move (scripted reply or engine reply) and
    /// records completion.
    private func advance() {
        let gen = generation
        switch player.status {
        case .autoTurn:
            Task {
                try? await Task.sleep(for: Self.autoDelay)
                guard gen == generation else { return }
                let before = player.fen
                if let move = player.playAuto() { tracker.apply(move, fenBefore: before) }
                advance()
            }
        case .opponentTurn:
            thinking = true
            Task {
                defer { if gen == generation { thinking = false } }
                do {
                    let uci = try await StockfishEngine.shared.opponentMove(
                        startFen: lesson.startFen, moves: player.played, elo: Self.engineElo)
                    guard gen == generation else { return }
                    let before = player.fen
                    if player.applyOpponent(uci) {
                        tracker.apply(uci, fenBefore: before)
                        advance()
                    } else {
                        engineFailed = true
                    }
                } catch {
                    guard gen == generation else { return }
                    Self.log.error("Engine reply failed: \(error.localizedDescription, privacy: .public)")
                    engineFailed = true
                }
            }
        case .completed:
            if let context { TrainingStore.completeLesson(lesson.id, in: context); TrainingStore.recordActivity(in: context) }
        case .userTurn, .failed:
            break
        }
    }

    private func engineHintMove() async {
        guard player.status == .userTurn, !thinking else { return }
        let gen = generation
        let request = AnalysisRequest(startFen: lesson.startFen, moves: player.played, depth: 16, multiPV: 1)
        if let result = try? await StockfishEngine.shared.analyze(request), gen == generation, player.status == .userTurn {
            engineHint = result.bestMove
        }
    }

    private static func squares(_ uci: String) -> (Square, Square) {
        (Square(String(uci.prefix(2))), Square(String(uci.dropFirst(2).prefix(2))))
    }
}
