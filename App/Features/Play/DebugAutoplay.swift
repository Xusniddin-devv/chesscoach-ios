#if DEBUG
import Foundation
import ChessCore
import StockfishKit

/// DEBUG-only launch arguments for simulator checks and screenshots.
///   -debugScreen picker      opens the bot picker
///   -debugAutoplay pip       starts a Training game against that bot as White and plays it
///                            (see `DebugAutoplay`)
enum DebugLaunch {
    static var autoplayBot: Bot? {
        UserDefaults.standard.string(forKey: "debugAutoplay").flatMap { id in Bot.all.first { $0.id == id } }
    }

    @MainActor static func apply(path openPicker: () -> Void, play: (PlaySetup) -> Void) {
        if UserDefaults.standard.string(forKey: "debugScreen") == "picker" { openPicker() }
        if let bot = autoplayBot {
            let mode: PlayMode = UserDefaults.standard.string(forKey: "debugMode") == "silent" ? .silent : .training
            play(PlaySetup(bot: bot, mode: mode, color: .white))
        }
    }
}

/// Plays the user's side with the engine at full strength, except one deliberate blunder
/// (the user's 4th move hangs the most valuable piece it can); in Silent mode it resigns
/// after 12 moves. When the game is over and graded it presses Done. On the first interrupt it waits,
/// shows the best move, waits, then takes back; later interrupts are continued. Every step
/// is logged with an `AUTOPLAY` prefix so a script can screenshot at the right moment.
@MainActor
enum DebugAutoplay {
    static func attachIfRequested(to model: PlayModel, onFinished: @escaping @MainActor () -> Void) {
        guard DebugLaunch.autoplayBot != nil else { return }
        Task {
            await run(model)
            try? await Task.sleep(for: .seconds(6))
            log("done")
            onFinished()
        }
    }

    private static func log(_ s: String) { print("AUTOPLAY \(s)") }

    private static func run(_ model: PlayModel) async {
        let session = model.session
        var userMoves = 0
        var blundered = false
        var tookBack = false
        while true {
            try? await Task.sleep(for: .milliseconds(300))
            switch session.phase {
            case .userTurn where model.interactive && session.mode == .silent && userMoves == 12:
                log("resign")
                session.resign()
            case .userTurn where model.interactive:
                let uci: String
                if userMoves == 3 && !blundered, let bad = hangingMove(session.fen) {
                    uci = bad
                    blundered = true
                    log("blunder \(uci)")
                } else {
                    let request = AnalysisRequest(startFen: session.startFen, moves: session.moves, depth: 10, multiPV: 1)
                    guard let best = try? await StockfishEngine.shared.analyze(request).bestMove,
                          session.phase == .userTurn else { continue }
                    uci = best
                }
                if model.move(uci) { userMoves += 1 }
            case .interrupted(let verdict):
                if tookBack {
                    log("interrupt \(verdict.classification.label) -> continue")
                    session.continueAfterInterrupt()
                } else {
                    log("interrupted \(verdict.classification.label)")
                    try? await Task.sleep(for: .seconds(4))
                    session.showBest()
                    log("showBest")
                    try? await Task.sleep(for: .seconds(4))
                    session.takeBack()
                    tookBack = true
                    userMoves -= 1
                    log("takeBack")
                }
            case .over:
                log("over \(session.pendingGradeCount)")
                while session.pendingGradeCount > 0 { try? await Task.sleep(for: .milliseconds(300)) }
                let graded = session.verdicts.values.sorted { $0.ply < $1.ply }
                log("graded " + graded.map { "\($0.san):\($0.classification.rawValue)" }.joined(separator: " "))
                return
            case .engineError:
                log("engineError -> retry")
                session.retry()
            default:
                break
            }
        }
    }

    /// The legal move that leaves the most valuable piece en prise, if any.
    private static func hangingMove(_ fen: String) -> String? {
        guard let position = Position(fen: fen) else { return nil }
        let board = Board(position: position)
        var best: (uci: String, value: Int)?
        for piece in position.pieces where piece.color == position.sideToMove && piece.kind != .king {
            for target in board.legalMoves(forPieceAt: piece.square) {
                let uci = piece.square.notation + target.notation
                guard let applied = Rules.apply(uci: uci, to: fen),
                      isEnPrise(fenAfter: applied.fenAfter, uci: uci, mover: piece.color) else { continue }
                let value = pieceValue(piece.kind)
                if value > (best?.value ?? 0) { best = (uci, value) }
            }
        }
        return best?.uci
    }
}
#endif
