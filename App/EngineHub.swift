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

    /// A game is on screen (PlayView). Review then shows saved data only: bulk analysis
    /// never runs while a `GameSession` is live (one engine per process).
    var isGameLive = false

    /// The player's level for Training thresholds and explanation wording: the rating
    /// estimate from saved games once there is one, else `PlayerProfile.defaultRating`.
    var playerRating = PlayerProfile.defaultRating

    /// The player's piece (rating tier from saved games; the Pawn until there is an estimate):
    /// their avatar in the player bars and on the game-over panel.
    var playerTier: RatingTier = .pawn

    /// Explanations in words below 1200, notation from there.
    var wording: MoveWording { playerRating < 1200 ? .words : .notation }

    init() {}

    func configure() async {
        await StockfishEngine.shared.configure(threads: Self.defaultThreads, hashMB: Self.defaultHashMB)
    }

    func makeSession(bot: Bot, userColor: Piece.Color, mode: PlayMode) -> GameSession {
        GameSession(bot: bot, userColor: userColor, mode: mode, engine: StockfishEngine.shared,
                    playerRating: playerRating)
    }

    func makeReview(record: GameRecord, wording: MoveWording = .words) -> ReviewModel {
        let review = ReviewModel(record: record, engine: StockfishEngine.shared, analysisAllowed: !isGameLive,
                                 wording: wording)
        review.userAvatar = playerTier.avatarAsset
        return review
    }
}
