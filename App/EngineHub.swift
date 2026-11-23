import SwiftUI
import Observation
import ChessCore
import StockfishKit

/// Owns access to the one shared engine and creates game sessions on it.
@MainActor
@Observable
final class EngineHub {
    /// One thread, 64 MB hash until device measurements (Plan 4).
    nonisolated static let defaultThreads = 1
    nonisolated static let defaultHashMB = 64

    init() {}

    func configure() async {
        await StockfishEngine.shared.configure(threads: Self.defaultThreads, hashMB: Self.defaultHashMB)
    }

    func makeSession(bot: Bot, userColor: Piece.Color, mode: PlayMode) -> GameSession {
        GameSession(bot: bot, userColor: userColor, mode: mode, engine: StockfishEngine.shared)
    }
}
