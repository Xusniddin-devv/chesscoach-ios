import SwiftUI
import Observation
import ChessCore
import StockfishKit

/// Owns access to the one shared engine and creates game sessions on it.
@MainActor
@Observable
final class EngineHub {
    private weak var current: GameSession?

    init() {}

    func configure() async {
        await StockfishEngine.shared.configure(threads: max(1, ProcessInfo.processInfo.activeProcessorCount - 2), hashMB: 64)
    }

    func makeSession(bot: Bot, userColor: Piece.Color, mode: PlayMode) -> GameSession {
        let session = GameSession(bot: bot, userColor: userColor, mode: mode, engine: StockfishEngine.shared)
        current = session
        return session
    }

    /// Call when the app becomes active: restarts the engine if the last call failed.
    func recoverIfNeeded() async {
        guard let current, current.hasEngineError else { return }
        await StockfishEngine.shared.restart()
    }
}
