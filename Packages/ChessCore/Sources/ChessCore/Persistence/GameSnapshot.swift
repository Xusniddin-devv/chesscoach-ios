import Foundation
import ChessKit

public enum PlayMode: String, Codable, Sendable {
    case training, silent
}

public enum GameResult: String, Codable, Sendable {
    case whiteWins = "1-0"
    case blackWins = "0-1"
    case draw = "1/2-1/2"
    case ongoing = "*"
}

/// A finished or abandoned game, as stored for later review.
///
/// Stored as JSON, so the format must survive app updates. Decoding is lenient (see the
/// `Decodable` extension below): every field that is not the game itself has a default, a
/// verdict that fails to decode is dropped rather than the game, and unknown keys are ignored.
/// `mode`, `startFen`, `moves` and `result` are required: a record without them is skipped.
/// A field added later must be decoded with `decodeIfPresent` and a default.
public struct GameSnapshot: Codable, Sendable, Equatable {
    /// Version of this stored format. Data saved before the field existed is version 1.
    public static let currentSchemaVersion = 1

    public var id: UUID
    public var date: Date
    public var botId: String
    public var userColor: Piece.Color
    public var mode: PlayMode
    public var startFen: String
    public var moves: [String]
    public var sans: [String]
    public var result: GameResult
    public var verdicts: [Verdict]
    public var analysisVersion: Int
    public var playerRatingUsed: Int
    public var schemaVersion: Int
    public var analysis: GameAnalysis?
    public var openingName: String?

    public init(id: UUID, date: Date, botId: String, userColor: Piece.Color, mode: PlayMode,
                startFen: String, moves: [String], sans: [String], result: GameResult,
                verdicts: [Verdict], analysisVersion: Int, playerRatingUsed: Int,
                schemaVersion: Int = GameSnapshot.currentSchemaVersion,
                analysis: GameAnalysis? = nil, openingName: String? = nil) {
        self.analysis = analysis
        self.openingName = openingName
        self.schemaVersion = schemaVersion
        self.id = id
        self.date = date
        self.botId = botId
        self.userColor = userColor
        self.mode = mode
        self.startFen = startFen
        self.moves = moves
        self.sans = sans
        self.result = result
        self.verdicts = verdicts
        self.analysisVersion = analysisVersion
        self.playerRatingUsed = playerRatingUsed
    }
}

extension GameSnapshot {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The game itself: without these there is nothing to show.
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        botId = try c.decode(String.self, forKey: .botId)
        userColor = try c.decode(Piece.Color.self, forKey: .userColor)
        moves = try c.decode([String].self, forKey: .moves)
        mode = try c.decode(PlayMode.self, forKey: .mode)
        startFen = try c.decode(String.self, forKey: .startFen)
        result = try c.decode(GameResult.self, forKey: .result)
        // Everything else has a default.
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        sans = try c.decodeIfPresent([String].self, forKey: .sans) ?? []
        analysisVersion = try c.decodeIfPresent(Int.self, forKey: .analysisVersion) ?? 1
        playerRatingUsed = try c.decodeIfPresent(Int.self, forKey: .playerRatingUsed) ?? PlayerProfile.defaultRating
        verdicts = (try c.decodeIfPresent([Lenient<Verdict>].self, forKey: .verdicts) ?? []).compactMap(\.value)
        // A broken or newer analysis block is dropped: the game stays viewable and can be re-analysed.
        analysis = (try? c.decodeIfPresent(GameAnalysis.self, forKey: .analysis)) ?? nil
        openingName = try? c.decodeIfPresent(String.self, forKey: .openingName)
    }
}

/// Decodes a value or nothing: one bad element of an array does not fail the whole array.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: any Decoder) throws {
        value = try? T(from: decoder)
    }
}

public func encodeSnapshot(_ snapshot: GameSnapshot) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(snapshot)
}

public func decodeSnapshot(_ data: Data) throws -> GameSnapshot {
    let decoder = JSONDecoder()
    return try decoder.decode(GameSnapshot.self, from: data)
}
