import Foundation

/// Lichess public API (no token): `api/user/{u}` for the account and its perfs,
/// `api/games/user/{u}?max=N&moves=true&pgnInJson=true` as NDJSON for the games.
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
                               title: user.title, avatarURL: nil, ratings: ratings)
    }

    public func recentGames(_ username: String, limit: Int = 20,
                            progress: @Sendable (Int) -> Void = { _ in }) async throws -> [String] {
        guard let name = sanitizedUsername(username) else { throw ImportError.userNotFound }
        var components = URLComponents(url: base.appendingPathComponent("api/games/user/\(name)"),
                                       resolvingAgainstBaseURL: false)!
        // Ask for a few extra: variant games are skipped below.
        components.queryItems = [
            URLQueryItem(name: "max", value: String(limit + 10)),
            URLQueryItem(name: "moves", value: "true"),
            URLQueryItem(name: "pgnInJson", value: "true"),
            URLQueryItem(name: "clocks", value: "false"),
            URLQueryItem(name: "evals", value: "false"),
        ]
        let data = try await http.fetch(components.url!, accept: "application/x-ndjson")
        return Self.parseNDJSON(data, limit: limit, progress: progress)
    }

    /// Standard games' PGNs from an NDJSON body, in order (Lichess sends newest first).
    static func parseNDJSON(_ data: Data, limit: Int, progress: @Sendable (Int) -> Void = { _ in }) -> [String] {
        var pgns: [String] = []
        for line in data.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
            guard let game = try? JSONDecoder().decode(Game.self, from: Data(line)),
                  (game.variant ?? "standard") == "standard",
                  let pgn = game.pgn, !pgn.isEmpty else { continue }
            pgns.append(pgn)
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
        var disabled: Bool?
        var perfs: [String: Perf]?
    }

    private struct Game: Decodable {
        var variant: String?
        var pgn: String?
    }
}
