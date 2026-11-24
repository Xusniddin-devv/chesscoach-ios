import Testing
import Foundation
@testable import ChessCore

/// Serves the committed fixture files by URL; anything else is 404. Records requests.
final class FixtureHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [String: (file: String, status: Int)] = [:]
    private var _requests: [(URL, String?)] = []

    var requests: [(URL, String?)] { lock.withLock { _requests } }

    func route(_ url: String, file: String, status: Int = 200) {
        lock.withLock { routes[url] = (file, status) }
    }

    func status(_ url: String, _ status: Int) {
        lock.withLock { routes[url] = ("", status) }
    }

    func get(_ url: URL, accept: String?) async throws -> (Data, Int) {
        let route = lock.withLock { () -> (file: String, status: Int)? in
            _requests.append((url, accept))
            return routes[url.absoluteString]
        }
        guard let route else { return (Data(), 404) }
        if route.file.isEmpty { return (Data(), route.status) }
        return (try fixture(route.file), route.status)
    }
}

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Import"))
    return try Data(contentsOf: url)
}

private let cc = "https://api.chess.com/pub/player/hikaru"

private func chessComRoutes() -> FixtureHTTP {
    let http = FixtureHTTP()
    http.route(cc, file: "chesscom-player.json")
    http.route(cc + "/stats", file: "chesscom-stats.json")
    http.route(cc + "/games/archives", file: "chesscom-archives.json")
    http.route(cc + "/games/2026/11", file: "chesscom-games-2026-11.json")
    http.route(cc + "/games/2026/10", file: "chesscom-games-2026-10.json")
    http.status(cc + "/games/2026/09", 500)
    return http
}

@Suite struct ImportClientTests {
    @Test func chessComProfileHasAvatarAndRapidFirst() async throws {
        let p = try await ChessComClient(http: chessComRoutes()).profile("Hikaru")
        #expect(p.username == "hikaru")
        #expect(p.title == "GM")
        #expect(p.avatarURL?.host == "images.chesscomfiles.com")
        #expect(p.ratings["rapid"] == 2838 && p.ratings["blitz"] == 3442)
        #expect(p.currentRating == 2838)
        #expect(p.currentRatingKey == "rapid")
        // Games across every time control's record; the account's opening date.
        #expect(p.gameCount == 73 + 11 + 4 + 205 + 69 + 220 + 17389 + 2576 + 1202 + 36294 + 5577 + 4400)
        #expect(p.joined == Date(timeIntervalSince1970: 1389043258))
    }

    @Test func chessComUnknownUserIsNotFound() async {
        await #expect(throws: ImportError.userNotFound) {
            try await ChessComClient(http: chessComRoutes()).profile("nobody_here")
        }
        await #expect(throws: ImportError.userNotFound) {
            try await ChessComClient(http: chessComRoutes()).profile("bad name/../x")
        }
    }

    @Test func chessComRateLimitSurfaces() async {
        let http = FixtureHTTP()
        http.status(cc, 429)
        await #expect(throws: ImportError.rateLimited) { try await ChessComClient(http: http).profile("hikaru") }
    }

    @Test func chessComGamesNewestFirstAcrossMonthsUpToLimit() async throws {
        let http = chessComRoutes()
        let counter = Counter()
        let pgns = try await ChessComClient(http: http).recentGames("hikaru", limit: 5) { counter.set($0) }
        #expect(pgns.count == 5)
        #expect(counter.value == 5)
        // November's last game (newest) comes first.
        let first = try #require(PGNGame.parse(pgns[0].pgn))
        let novemberLast = try JSONDecoder().decode(MonthProbe.self, from: fixture("chesscom-games-2026-11.json")).games.last!.pgn
        #expect(first == PGNGame.parse(novemberLast))
        // The broken September archive was never needed.
        #expect(!http.requests.contains { $0.0.absoluteString.hasSuffix("2026/09") })
    }

    @Test func chessComSkipsABrokenMonth() async throws {
        let pgns = try await ChessComClient(http: chessComRoutes()).recentGames("hikaru", limit: 20)
        #expect(pgns.count == 6)
    }

    @Test func lichessProfileAndNDJSONGames() async throws {
        let http = FixtureHTTP()
        http.route("https://lichess.org/api/user/DrNykterstein", file: "lichess-user.json")
        http.route("https://lichess.org/api/games/user/DrNykterstein?max=12&moves=true&pgnInJson=true&clocks=false&evals=true&accuracy=true",
                   file: "lichess-games.ndjson")
        let client = LichessClient(http: http)
        let p = try await client.profile("DrNykterstein")
        #expect(p.platform == .lichess && p.title == "GM")
        // Rapid has no games on this account (Lichess still reports a provisional 2500): skipped.
        #expect(p.ratings["rapid"] == nil && p.ratings["blitz"] == 3194)
        #expect(p.currentRating == 3194 && p.currentRatingKey == "blitz")
        #expect(p.gameCount == 10455)
        let pgns = try await client.recentGames("DrNykterstein", limit: 2)
        #expect(pgns.count == 2)
        #expect(http.requests.last?.1 == "application/x-ndjson")
    }

    @Test func lichessUnknownUser() async {
        await #expect(throws: ImportError.userNotFound) {
            try await LichessClient(http: FixtureHTTP()).profile("ghost")
        }
    }
}

private struct MonthProbe: Decodable { struct G: Decodable { var pgn: String }; var games: [G] }

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.withLock { _value } }
    func set(_ v: Int) { lock.withLock { _value = v } }
}

@Suite struct PGNImportTests {
    @Test func tokensDropCommentsVariationsNAGsAndNumbers() {
        let text = "1. e4 {[%clk 0:03:00]} 1... e5 2.Nf3 (2. f4 exf4) Nc6 $1 3. Bb5 a6?! ; note\n"
        #expect(PGNGame.tokens(text) == ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6?!"])
        #expect(PGNGame.tokens("1. d4 d5 1/2-1/2") == ["d4", "d5"])
    }

    @Test func chessComGameBecomesASnapshotFromTheUsersSide() throws {
        let games = try JSONDecoder().decode(MonthProbe.self, from: fixture("chesscom-games-2026-11.json")).games
        for g in games {
            let s = try PGNImporter.snapshot(pgn: g.pgn, username: "HIKARU", platform: .chesscom)
            let pgn = try #require(PGNGame.parse(g.pgn))
            #expect(s.source == "chesscom" && s.isImported)
            #expect(s.moves.count == pgn.sans.count)
            #expect(Rules.fen(startFen: s.startFen, moves: s.moves) != nil)
            let white = pgn.tags["White"]!.lowercased() == "hikaru"
            #expect(s.userColor == (white ? .white : .black))
            #expect(s.opponentName == pgn.tags[white ? "Black" : "White"])
            #expect(s.opponentRating == Int(pgn.tags[white ? "BlackElo" : "WhiteElo"]!))
            #expect(s.playerRatingUsed == Int(pgn.tags[white ? "WhiteElo" : "BlackElo"]!))
            #expect(s.result.rawValue == pgn.tags["Result"])
            #expect(s.externalURL?.hasPrefix("https://www.chess.com/game/") == true)
        }
    }

    @Test func lichessGameDateAndStableId() throws {
        let line = try #require(String(data: try fixture("lichess-games.ndjson"), encoding: .utf8)?.split(separator: "\n").first)
        struct G: Decodable { var pgn: String }
        let pgn = try JSONDecoder().decode(G.self, from: Data(line.utf8)).pgn
        let a = try PGNImporter.snapshot(pgn: pgn, username: "drnykterstein", platform: .lichess)
        let b = try PGNImporter.snapshot(pgn: pgn, username: "drnykterstein", platform: .lichess)
        #expect(a.id == b.id)
        #expect(a.userColor == .white && a.result == .whiteWins && a.opponentName == "Night-King96")
        let utc = Calendar(identifier: .gregorian)
        var c = utc; c.timeZone = TimeZone(identifier: "UTC")!
        #expect(c.dateComponents([.year, .month, .day, .hour], from: a.date) == DateComponents(year: 2026, month: 10, day: 14, hour: 18))
    }

    @Test func someoneElsesGameIsRejected() throws {
        let pgn = "[White \"a\"]\n[Black \"b\"]\n[Result \"1-0\"]\n\n1. e4 e5 1-0"
        #expect(throws: PGNImporter.Failure.notUsersGame) {
            try PGNImporter.snapshot(pgn: pgn, username: "c", platform: .lichess)
        }
    }

    @Test func illegalMoveIsReportedWithPly() {
        let pgn = "[White \"me\"]\n[Black \"b\"]\n\n1. e4 e5 2. Ke3 1-0"
        #expect(throws: PGNImporter.Failure.illegalMove(ply: 3, san: "Ke3")) {
            try PGNImporter.snapshot(pgn: pgn, username: "me", platform: .lichess)
        }
    }

    @Test func castlingPromotionAndCustomStart() throws {
        let castle = "[White \"me\"]\n[Black \"b\"]\n\n1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. O-O Nf6 *"
        #expect(try PGNImporter.snapshot(pgn: castle, username: "me", platform: .lichess).moves.last == "g8f6")
        #expect(try PGNImporter.snapshot(pgn: castle, username: "me", platform: .lichess).moves[6] == "e1g1")
        let promo = "[White \"me\"]\n[Black \"b\"]\n[SetUp \"1\"]\n[FEN \"4k3/P7/8/8/8/8/8/4K3 w - - 0 1\"]\n\n1. a8=Q+ *"
        let s = try PGNImporter.snapshot(pgn: promo, username: "me", platform: .lichess)
        #expect(s.moves == ["a7a8q"])
        #expect(s.startFen == "4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
    }

    @Test func importedFieldsSurviveEncodingAndOldDataDecodes() throws {
        var s = GameSnapshot(id: UUID(), date: Date(timeIntervalSince1970: 0), botId: "chesscom", userColor: .black,
                             mode: .silent, startFen: Rules.startFen, moves: ["e2e4"], sans: ["e4"], result: .ongoing,
                             verdicts: [], analysisVersion: 1, playerRatingUsed: 900)
        s.source = "chesscom"; s.opponentName = "x"; s.opponentRating = 1000; s.externalURL = "https://e"
        #expect(try decodeSnapshot(encodeSnapshot(s)) == s)
        s.source = nil; s.opponentName = nil; s.opponentRating = nil; s.externalURL = nil
        #expect(try decodeSnapshot(encodeSnapshot(s)).source == nil)
    }
}
