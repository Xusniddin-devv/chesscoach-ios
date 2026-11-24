import Foundation

/// Lichess public API (no token): `api/user/{u}` for the account and its perfs,
/// `api/games/user/{u}?max=N&moves=true&pgnInJson=true&evals=true&accuracy=true` as NDJSON for
/// the games; games analysed on Lichess carry per-ply evals and each side's accuracy.
public struct LichessClient: GameImportClient {
    public let http: any HTTPClient
    public let base: URL
    public var platform: ImportPlatform { .lichess }

    public init(http: any HTTPClient = URLSessionHTTPClient(),
                base: URL = URL(string: "https://lichess.org/")!) {
        self.http = http
        self.base = base
    }

    public func profile(_ username: String) async throws -> PlatformProfile {
        guard let name = sanitizedUsername(username) else { throw ImportError.userNotFound }
        let data = try await http.fetch(base.appendingPathComponent("api/user/\(name)"))
        let user = try JSONDecoder().decode(User.self, from: data)
        // Closed accounts answer 200 with `disabled`; banned ones with `tosViolation`.
        if user.disabled == true || user.username == nil { throw ImportError.userNotFound }
        var ratings: [String: Int] = [:]
        for key in ["rapid", "blitz", "bullet", "classical"] {
            if let perf = user.perfs?[key], let rating = perf.rating, (perf.games ?? 1) > 0 { ratings[key] = rating }
        }
        return PlatformProfile(platform: .lichess, username: user.username ?? name, realName: nil,
                               title: user.title, avatarURL: nil, ratings: ratings,
                               gameCount: user.count?.all,
                               joined: user.createdAt.map { Date(timeIntervalSince1970: $0 / 1000) })
    }

    public func recentGames(_ username: String, limit: Int = 20,
                            progress: @Sendable (Int) -> Void = { _ in }) async throws -> [ImportedGame] {
        guard let name = sanitizedUsername(username) else { throw ImportError.userNotFound }
        var components = URLComponents(url: base.appendingPathComponent("api/games/user/\(name)"),
                                       resolvingAgainstBaseURL: false)!
        // Ask for a few extra: variant games are skipped below.
        components.queryItems = [
            URLQueryItem(name: "max", value: String(limit + 10)),
            URLQueryItem(name: "moves", value: "true"),
            URLQueryItem(name: "pgnInJson", value: "true"),
            URLQueryItem(name: "clocks", value: "false"),
            URLQueryItem(name: "evals", value: "true"),
            URLQueryItem(name: "accuracy", value: "true"),
        ]
        let data = try await http.fetch(components.url!, accept: "application/x-ndjson")
        return Self.parseNDJSON(data, limit: limit, progress: progress)
    }

    /// Auto-sync: games created since `since` (Lichess filters by `since`, newest first), up to
    /// the first stored game.
    public func games(_ username: String, since: Date, limit: Int,
                      isKnown: @Sendable (ImportedGame) -> Bool) async throws -> [ImportedGame] {
        guard let name = sanitizedUsername(username) else { throw ImportError.userNotFound }
        var components = URLComponents(url: base.appendingPathComponent("api/games/user/\(name)"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "since", value: String(Int64(since.timeIntervalSince1970.rounded(.down)) * 1000)),
            URLQueryItem(name: "max", value: String(limit)),
            URLQueryItem(name: "moves", value: "true"),
            URLQueryItem(name: "pgnInJson", value: "true"),
            URLQueryItem(name: "clocks", value: "false"),
            URLQueryItem(name: "evals", value: "true"),
            URLQueryItem(name: "accuracy", value: "true"),
        ]
        let data = try await http.fetch(components.url!, accept: "application/x-ndjson")
        return Self.parseNDJSON(data, limit: limit, stopAt: isKnown)
    }

    /// Standard games' PGNs from an NDJSON body, in order (Lichess sends newest first), up to
    /// the first one `stopAt` matches.
    static func parseNDJSON(_ data: Data, limit: Int, progress: @Sendable (Int) -> Void = { _ in },
                            stopAt: (ImportedGame) -> Bool = { _ in false }) -> [ImportedGame] {
        var pgns: [ImportedGame] = []
        for line in data.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
            guard let game = try? JSONDecoder().decode(Game.self, from: Data(line)),
                  (game.variant ?? "standard") == "standard",
                  let pgn = game.pgn, !pgn.isEmpty else { continue }
            let white = game.players?.white?.analysis?.accuracy
            let black = game.players?.black?.analysis?.accuracy
            let accuracy = white == nil && black == nil ? nil : PlatformAccuracy(white: white, black: black, source: "lichess")
            let imported = ImportedGame(pgn: pgn, accuracy: accuracy, evals: game.analysis?.isEmpty == false ? game.analysis : nil)
            if stopAt(imported) { break }
            pgns.append(imported)
            progress(pgns.count)
            if pgns.count == limit { break }
        }
        return pgns
    }

    // MARK: Wire format

    private struct User: Decodable {
        struct Perf: Decodable { var rating: Int?; var games: Int? }
        var username: String?
        var title: String?
        struct Count: Decodable { var all: Int? }
        var disabled: Bool?
        var perfs: [String: Perf]?
        var count: Count?
        var createdAt: Double?
    }

    private struct Game: Decodable {
        struct Players: Decodable {
            struct Side: Decodable {
                struct Analysis: Decodable { var accuracy: Double? }
                var analysis: Analysis?
            }
            var white: Side?
            var black: Side?
        }
        var variant: String?
        var pgn: String?
        var players: Players?
        var analysis: [PlatformEval]?

        // Lenient: anything odd outside the PGN is dropped, the game is kept.
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            variant = try? c.decodeIfPresent(String.self, forKey: .variant)
            pgn = try? c.decodeIfPresent(String.self, forKey: .pgn)
            players = (try? c.decodeIfPresent(Players.self, forKey: .players)) ?? nil
            analysis = (try? c.decodeIfPresent([PlatformEval].self, forKey: .analysis)) ?? nil
        }
        private enum CodingKeys: String, CodingKey { case variant, pgn, players, analysis }
    }
}
