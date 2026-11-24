import Foundation

/// Auto-sync of the linked chess.com / Lichess account: the games played since the newest
/// one already stored, newest first. The cursor is that stored game's date (nothing else is
/// kept); a client reads newest first and stops at the first game it already has, so a sync
/// with nothing new costs one or two requests. Games are deduplicated by the platform game id
/// (`PGNImporter.stableId`), the same id onboarding's import gives them.
public enum GameSync {
    /// At most this many games per sync (a first sync, or a long break).
    public static let limit = 20

    /// The newest stored game's date for `platform`: games of the other platform (an earlier
    /// linked account) never move it.
    public static func cursor(platform: ImportPlatform, stored: [GameSnapshot]) -> Date? {
        stored.filter { $0.source == platform.rawValue }.map(\.date).max()
    }

    /// The account's games not stored yet, newest first, as snapshots from the user's side.
    /// Throws the client's errors (`ImportError.rateLimited`, `.network`) for the caller's backoff.
    public static func newGames(client: any GameImportClient, username: String, stored: [GameSnapshot],
                                limit: Int = limit) async throws -> [GameSnapshot] {
        let platform = client.platform
        let known = Set(stored.map(\.id))
        let fetched: [ImportedGame]
        if let since = cursor(platform: platform, stored: stored) {
            fetched = try await client.games(username, since: since, limit: limit) { game in
                PGNImporter.stableId(platform: platform, pgn: game.pgn).map(known.contains) ?? false
            }
        } else {
            fetched = try await client.recentGames(username, limit: limit, progress: { _ in })
        }
        var seen = known
        var result: [GameSnapshot] = []
        for game in fetched {
            guard let snapshot = try? PGNImporter.snapshot(game: game, username: username, platform: platform),
                  seen.insert(snapshot.id).inserted else { continue }
            result.append(snapshot)
        }
        return result.sorted { $0.date > $1.date }
    }
}

extension GameImportClient {
    /// Fallback for clients without a cursor (test fakes): the recent games, up to the first known one.
    public func games(_ username: String, since: Date, limit: Int,
                      isKnown: @Sendable (ImportedGame) -> Bool) async throws -> [ImportedGame] {
        let recent = try await recentGames(username, limit: limit, progress: { _ in })
        return Array(recent.prefix { !isKnown($0) })
    }
}

extension PGNImporter {
    /// The id a game gets when imported (`snapshot(pgn:)`), from its PGN tags alone.
    public static func stableId(platform: ImportPlatform, pgn: String) -> UUID? {
        guard let game = PGNGame.parse(pgn) else { return nil }
        return stableId(platform: platform, key: game.tags["Link"] ?? game.tags["Site"] ?? pgn)
    }

    /// The game's start (UTC tags), as `snapshot(pgn:)` dates it.
    static func date(pgn: String) -> Date? {
        PGNGame.parse(pgn).flatMap { date($0.tags) }
    }
}

/// When the next auto-sync may run: at most every `throttle` on its own, any time on a pull to
/// refresh, and after a rate limit or a network failure not before `retryAfter` (15 min,
/// doubling per failure, capped at `maxBackoff`). Stored as JSON in the app's defaults.
public struct SyncSchedule: Codable, Equatable, Sendable {
    public static let throttle: TimeInterval = 15 * 60
    public static let maxBackoff: TimeInterval = 6 * 3_600

    public var lastAttempt: Date?
    public var lastSuccess: Date?
    public var failures = 0
    public var retryAfter: Date?

    public init() {}

    public func isDue(now: Date, force: Bool) -> Bool {
        if let retryAfter, now < retryAfter { return false }
        if force { return true }
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= Self.throttle
    }

    public mutating func started(at now: Date) {
        lastAttempt = now
    }

    public mutating func succeeded(at now: Date) {
        lastSuccess = now
        failures = 0
        retryAfter = nil
    }

    /// Any failure backs off; an account that is gone (`userNotFound`) waits the longest.
    public mutating func failed(at now: Date, error: any Error) {
        failures += 1
        let wait = (error as? ImportError) == .userNotFound
            ? Self.maxBackoff
            : min(Self.throttle * pow(2, Double(min(failures, 16) - 1)), Self.maxBackoff)
        retryAfter = now.addingTimeInterval(wait)
    }
}
