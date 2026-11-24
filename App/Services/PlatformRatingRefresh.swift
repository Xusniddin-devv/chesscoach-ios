import Foundation
import SwiftData
import ChessCore

/// Keeps an imported player's rating current: at most once a day it asks chess.com / Lichess
/// for the account's rating (the same time control preference as onboarding's reveal,
/// `PlatformProfile.currentRating`) and saves it on the profile. Any failure is silent:
/// the saved rating stays.
@MainActor
enum PlatformRatingRefresh {
    static let lastAttemptKey = "platformRating.lastRefresh"
    static let interval: TimeInterval = 24 * 3_600

    static func refreshIfDue(in context: ModelContext, now: Date = .now, defaults: UserDefaults = .standard,
                             client: (ImportPlatform) -> any GameImportClient = PlatformRatingRefresh.client) async {
        guard let profile = ProfileStore.profile(in: context), let platform = profile.importPlatform,
              !profile.username.isEmpty else { return }
        if let last = defaults.object(forKey: lastAttemptKey) as? Date, now.timeIntervalSince(last) < interval { return }
        defaults.set(now, forKey: lastAttemptKey)
        let username = profile.username
        guard let fresh = (try? await client(platform).profile(username))?.currentRating,
              fresh != profile.currentRating else { return }
        profile.currentRating = fresh
        profile.updated = now
        context.saveReporting("your rating")
    }

    nonisolated static func client(_ platform: ImportPlatform) -> any GameImportClient {
        switch platform {
        case .chesscom: ChessComClient()
        case .lichess: LichessClient()
        }
    }
}
