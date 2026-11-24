import Testing
import Foundation
@testable import ChessCore

// Auto-sync of the linked account: only games newer than the newest stored one, newest first,
// stopping at the first game already stored. Fixtures: hikaru's chess.com archives
// (2026/09 broken, 2026/10, 2026/11) and DrNykterstein's Lichess NDJSON.

private let cc = "https://api.chess.com/pub/player/hikaru"

private func chessCom() -> FixtureHTTP {
    let http = FixtureHTTP()
    http.route(cc + "/games/archives", file: "chesscom-archives.json")
    http.route(cc + "/games/2026/11", file: "chesscom-games-2026-11.json")
    http.route(cc + "/games/2026/10", file: "chesscom-games-2026-10.json")
    http.status(cc + "/games/2026/09", 500)
    return http
}

private struct MonthFile: Decodable { struct G: Decodable { var pgn: String }; var games: [G] }

/// The stored snapshots of a month file's games (oldest first, as the file lists them).
private func stored(_ file: String) throws -> [GameSnapshot] {
    try JSONDecoder().decode(MonthFile.self, from: fixture(file)).games.map {
        try PGNImporter.snapshot(pgn: $0.pgn, username: "hikaru", platform: .chesscom)
    }
}

private func lichessStored() throws -> [GameSnapshot] {
    struct G: Decodable { var pgn: String }
    let lines = try #require(String(data: try fixture("lichess-games.ndjson"), encoding: .utf8)).split(separator: "\n")
    return try lines.map {
        try PGNImporter.snapshot(pgn: JSONDecoder().decode(G.self, from: Data($0.utf8)).pgn,
                                 username: "drnykterstein", platform: .lichess)
    }
}

private func requested(_ http: FixtureHTTP) -> [String] { http.requests.map(\.0.absoluteString) }

@Suite struct GameSyncTests {
    // MARK: chess.com

    @Test func chessComFirstSyncIsTheRecentGames() async throws {
        let result = try await GameSync.newGames(client: ChessComClient(http: chessCom()), username: "hikaru", stored: [])
        #expect(result.count == 6)  // the broken September archive is skipped
        #expect(result.map(\.date) == result.map(\.date).sorted(by: >))
    }

    @Test func chessComFetchesOnlyFromTheLastSyncedMonthAndStopsAtAKnownGame() async throws {
        let http = chessCom()
        let november = try stored("chesscom-games-2026-11.json")
        // The oldest November game is the newest stored one.
        let result = try await GameSync.newGames(client: ChessComClient(http: http), username: "hikaru", stored: [november[0]])
        #expect(result.map(\.id) == [november[2].id, november[1].id])
        #expect(result.allSatisfy { $0.source == "chesscom" && $0.opponentName == "WiktorGolis" })
        #expect(!requested(http).contains(cc + "/games/2026/10"))
        #expect(!requested(http).contains(cc + "/games/2026/09"))
    }

    @Test func chessComNothingNewMeansOneMonthAndNoGames() async throws {
        let http = chessCom()
        let november = try stored("chesscom-games-2026-11.json")
        let result = try await GameSync.newGames(client: ChessComClient(http: http), username: "hikaru", stored: november)
        #expect(result.isEmpty)
        #expect(requested(http) == [cc + "/games/archives", cc + "/games/2026/11"])
    }

    @Test func chessComCursorInAnEarlierMonthReadsForwardFromIt() async throws {
        let http = chessCom()
        let october = try stored("chesscom-games-2026-10.json")
        // Cursor in October (by month URL): November and October are read, September is not.
        var newest = october[2]
        newest.date = try #require(ISO8601DateFormatter().date(from: "2026-10-31T23:00:00Z"))
        let result = try await GameSync.newGames(client: ChessComClient(http: http), username: "hikaru", stored: [newest])
        // Stops at the stored game (same id) inside October.
        #expect(result.count == 3)
        #expect(!result.contains { $0.id == newest.id })
        #expect(requested(http).contains(cc + "/games/2026/10"))
        #expect(!requested(http).contains(cc + "/games/2026/09"))
    }

    @Test func otherPlatformsGamesDoNotMoveTheCursor() async throws {
        let http = chessCom()
        let lichess = try lichessStored()
        let result = try await GameSync.newGames(client: ChessComClient(http: http), username: "hikaru", stored: lichess)
        #expect(result.count == 6)
    }

    @Test func cursorIsTheNewestStoredGameOfThatPlatform() throws {
        let november = try stored("chesscom-games-2026-11.json")
        let lichess = try lichessStored()
        let cursor = GameSync.cursor(platform: .chesscom, stored: november + lichess)
        #expect(cursor == november.map(\.date).max())
        #expect(GameSync.cursor(platform: .lichess, stored: november) == nil)
    }

    // MARK: Lichess

    @Test func lichessAsksSinceTheCursorAndStopsAtAKnownGame() async throws {
        let all = try lichessStored()  // newest first
        let known = all[2]
        let since = Int64(known.date.timeIntervalSince1970) * 1000
        let http = FixtureHTTP()
        http.route("https://lichess.org/api/games/user/DrNykterstein?since=\(since)&max=\(GameSync.limit)&moves=true&pgnInJson=true&clocks=false&evals=true&accuracy=true",
                   file: "lichess-games.ndjson")
        let result = try await GameSync.newGames(client: LichessClient(http: http), username: "DrNykterstein", stored: [known])
        #expect(result.map(\.id) == [all[0].id, all[1].id])
        #expect(http.requests.last?.1 == "application/x-ndjson")
    }

    @Test func lichessFirstSyncHasNoSince() async throws {
        let http = FixtureHTTP()
        http.route("https://lichess.org/api/games/user/DrNykterstein?max=\(GameSync.limit + 10)&moves=true&pgnInJson=true&clocks=false&evals=true&accuracy=true",
                   file: "lichess-games.ndjson")
        let result = try await GameSync.newGames(client: LichessClient(http: http), username: "DrNykterstein", stored: [])
        #expect(result.count == 3)
    }

    @Test func rateLimitSurfacesForBackoff() async {
        let http = FixtureHTTP()
        http.status(cc + "/games/archives", 429)
        let november = try? stored("chesscom-games-2026-11.json")
        await #expect(throws: ImportError.rateLimited) {
            try await GameSync.newGames(client: ChessComClient(http: http), username: "hikaru", stored: november ?? [])
        }
    }

    // MARK: Schedule

    @Test func scheduleThrottlesAndBacksOff() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var s = SyncSchedule()
        #expect(s.isDue(now: t0, force: false))
        s.started(at: t0)
        s.succeeded(at: t0)
        #expect(!s.isDue(now: t0.addingTimeInterval(10 * 60), force: false))
        #expect(s.isDue(now: t0.addingTimeInterval(10 * 60), force: true))  // pull to refresh
        #expect(s.isDue(now: t0.addingTimeInterval(15 * 60), force: false))

        // 429 / offline: 15 min, then 30, 60 ... capped at 6 h; even a pull waits it out.
        s.started(at: t0)
        s.failed(at: t0, error: ImportError.rateLimited)
        #expect(!s.isDue(now: t0.addingTimeInterval(14 * 60), force: true))
        #expect(s.isDue(now: t0.addingTimeInterval(15 * 60), force: false))
        s.failed(at: t0, error: ImportError.network)
        #expect(s.retryAfter == t0.addingTimeInterval(30 * 60))
        for _ in 0..<10 { s.failed(at: t0, error: ImportError.network) }
        #expect(s.retryAfter == t0.addingTimeInterval(SyncSchedule.maxBackoff))
        s.succeeded(at: t0)
        #expect(s.failures == 0 && s.retryAfter == nil)
    }

    @Test func scheduleRoundTripsThroughDefaultsData() throws {
        var s = SyncSchedule()
        s.failed(at: Date(timeIntervalSince1970: 1_800_000_000), error: ImportError.rateLimited)
        let back = try JSONDecoder().decode(SyncSchedule.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }
}
