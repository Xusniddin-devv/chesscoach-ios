import Foundation

/// chess.com published-data API (no key): `pub/player/{u}`, `pub/player/{u}/stats`,
/// `pub/player/{u}/games/archives` and the monthly archives, read newest month first.
public struct ChessComClient: GameImportClient {
    public let http: any HTTPClient
    public let base: URL
    public var platform: ImportPlatform { .chesscom }

    public init(http: any HTTPClient = URLSessionHTTPClient(),
                base: URL = URL(string: "https://api.chess.com/pub/player/")!) {
        self.http = http
        self.base = base
    }

    private func url(_ username: String, _ path: String = "") throws -> URL {
        guard let name = sanitizedUsername(username)?.lowercased() else { throw ImportError.userNotFound }
        return base.appendingPathComponent(name + path)
    }

    public func profile(_ username: String) async throws -> PlatformProfile {
        let player = try JSONDecoder().decode(Player.self, from: try await http.fetch(url(username)))
        // Stats are a nicety: a failure there must not hide an existing account.
        let stats = try? JSONDecoder().decode(Stats.self, from: try await http.fetch(url(username, "/stats")))
        var ratings: [String: Int] = [:]
        if let r = stats?.chess_rapid?.last?.rating { ratings["rapid"] = r }
        if let r = stats?.chess_blitz?.last?.rating { ratings["blitz"] = r }
        if let r = stats?.chess_bullet?.last?.rating { ratings["bullet"] = r }
        if let r = stats?.chess_daily?.last?.rating { ratings["daily"] = r }
        let modes = [stats?.chess_rapid, stats?.chess_blitz, stats?.chess_bullet, stats?.chess_daily].compactMap { $0?.record }
        let games = modes.reduce(0) { $0 + ($1.win ?? 0) + ($1.loss ?? 0) + ($1.draw ?? 0) }
        return PlatformProfile(platform: .chesscom, username: player.username ?? username,
                               realName: player.name, title: player.title,
                               avatarURL: player.avatar.flatMap(URL.init(string:)), ratings: ratings,
                               gameCount: modes.isEmpty ? nil : games,
                               joined: player.joined.map { Date(timeIntervalSince1970: TimeInterval($0)) })
    }

    public func recentGames(_ username: String, limit: Int = 20,
                            progress: @Sendable (Int) -> Void = { _ in }) async throws -> [ImportedGame] {
        let archives = try JSONDecoder().decode(Archives.self, from: try await http.fetch(url(username, "/games/archives")))
        var pgns: [ImportedGame] = []
        // Archives are listed oldest first; games inside a month too.
        // Two years of months at most: an inactive account should not cost a hundred requests.
        for archive in archives.archives.reversed().prefix(24) {
            try Task.checkCancellation()
            guard pgns.count < limit, let monthURL = URL(string: archive),
                  monthURL.host == base.host else { continue }
            let month: Month
            do {
                month = try JSONDecoder().decode(Month.self, from: try await http.fetch(monthURL))
            } catch ImportError.rateLimited {
                throw ImportError.rateLimited
            } catch ImportError.network {
                throw ImportError.network
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue  // one broken month: keep the rest
            }
            for game in month.games.reversed() where (game.rules ?? "chess") == "chess" {
                guard let pgn = game.pgn, !pgn.isEmpty else { continue }
                // Present only for games reviewed on chess.com.
                let accuracy = game.accuracies.flatMap { a in
                    a.white == nil && a.black == nil ? nil : PlatformAccuracy(white: a.white, black: a.black, source: "chesscom")
                }
                pgns.append(ImportedGame(pgn: pgn, accuracy: accuracy))
                progress(pgns.count)
                if pgns.count == limit { break }
            }
            if pgns.count >= limit { break }
        }
        return pgns
    }

    // MARK: Wire format

    private struct Player: Decodable {
        var username: String?
        var name: String?
        var title: String?
        var avatar: String?
        var joined: Int?
    }

    private struct Stats: Decodable {
        struct Mode: Decodable {
            struct Last: Decodable { var rating: Int? }
            struct Record: Decodable { var win: Int?; var loss: Int?; var draw: Int? }
            var last: Last?
            var record: Record?
        }
        var chess_rapid: Mode?
        var chess_blitz: Mode?
        var chess_bullet: Mode?
        var chess_daily: Mode?
    }

    private struct Archives: Decodable { var archives: [String] }

    private struct Month: Decodable {
        struct Game: Decodable {
            struct Accuracies: Decodable { var white: Double?; var black: Double? }
            var pgn: String?
            var rules: String?
            var accuracies: Accuracies?

            // Lenient: a game with an odd `accuracies` value keeps its PGN.
            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                pgn = try? c.decodeIfPresent(String.self, forKey: .pgn)
                rules = try? c.decodeIfPresent(String.self, forKey: .rules)
                accuracies = (try? c.decodeIfPresent(Accuracies.self, forKey: .accuracies)) ?? nil
            }
            private enum CodingKeys: String, CodingKey { case pgn, rules, accuracies }
        }
        var games: [Game]
    }
}
