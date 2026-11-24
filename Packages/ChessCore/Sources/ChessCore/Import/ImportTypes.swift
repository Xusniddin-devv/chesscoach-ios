import Foundation

/// Where imported games come from.
public enum ImportPlatform: String, Codable, Sendable, CaseIterable {
    case chesscom, lichess

    public var title: String {
        switch self {
        case .chesscom: "chess.com"
        case .lichess: "Lichess"
        }
    }
}

public enum ImportError: Error, Equatable, Sendable {
    /// The platform has no (open) account with that name.
    case userNotFound
    /// HTTP 429: try again in a minute.
    case rateLimited
    /// Offline, timeout, DNS…
    case network
    /// Any other unexpected status or body.
    case badResponse(Int)
}

/// The account as the platform reports it.
public struct PlatformProfile: Sendable, Equatable, Codable {
    public var platform: ImportPlatform
    /// As typed by the platform (display case), e.g. "Hikaru".
    public var username: String
    public var realName: String?
    public var title: String?
    public var avatarURL: URL?
    /// Ratings by time control key: "rapid", "blitz", "bullet", "daily"/"classical".
    public var ratings: [String: Int]
    /// Games played there (all time controls), when the platform says.
    public var gameCount: Int?
    /// When the account was opened.
    public var joined: Date?

    public init(platform: ImportPlatform, username: String, realName: String? = nil, title: String? = nil,
                avatarURL: URL? = nil, ratings: [String: Int] = [:], gameCount: Int? = nil, joined: Date? = nil) {
        self.gameCount = gameCount
        self.joined = joined
        self.platform = platform
        self.username = username
        self.realName = realName
        self.title = title
        self.avatarURL = avatarURL
        self.ratings = ratings
    }

    /// Order in which a time control speaks for the player's level (spec: rapid, then blitz).
    public static let ratingPreference = ["rapid", "blitz", "classical", "bullet", "daily"]

    /// The rating that stands for the player: rapid, then blitz, then the rest.
    public var currentRating: Int? {
        currentRatingKey.flatMap { ratings[$0] }
    }

    public var currentRatingKey: String? {
        Self.ratingPreference.first { ratings[$0] != nil }
    }
}

/// Minimal HTTP seam so the clients run against fixtures in tests.
public protocol HTTPClient: Sendable {
    /// Returns the body and the status code. Throws only for transport failures.
    func get(_ url: URL, accept: String?) async throws -> (Data, Int)
}

/// URLSession-backed client. Lichess rejects requests without a User-Agent, so one is always sent.
public struct URLSessionHTTPClient: HTTPClient {
    public let session: URLSession
    public let userAgent: String

    public init(session: URLSession = .shared, userAgent: String = "ChessCoach-iOS/1.0") {
        self.session = session
        self.userAgent = userAgent
    }

    public func get(_ url: URL, accept: String?) async throws -> (Data, Int) {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ImportError.network
        }
    }
}

/// One platform's import API.
public protocol GameImportClient: Sendable {
    var platform: ImportPlatform { get }
    /// Throws `ImportError.userNotFound` for an unknown or closed account.
    func profile(_ username: String) async throws -> PlatformProfile
    /// The latest standard-chess games, newest first, at most `limit`, with any accuracy or
    /// evals the platform already has. `progress(fetched)` fires as games arrive.
    func recentGames(_ username: String, limit: Int,
                     progress: @Sendable (Int) -> Void) async throws -> [ImportedGame]
}

extension HTTPClient {
    /// GET and map the status: 404 → userNotFound, 429 → rateLimited, other non-2xx → badResponse.
    func fetch(_ url: URL, accept: String? = nil) async throws -> Data {
        let (data, status) = try await get(url, accept: accept)
        switch status {
        case 200..<300: return data
        case 404, 410: throw ImportError.userNotFound
        case 429: throw ImportError.rateLimited
        default: throw ImportError.badResponse(status)
        }
    }
}

/// Usernames go into URL paths: keep only what both platforms allow.
func sanitizedUsername(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
    guard !trimmed.isEmpty, trimmed.count <= 30,
          trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) && $0.isASCII }) else { return nil }
    return trimmed
}
