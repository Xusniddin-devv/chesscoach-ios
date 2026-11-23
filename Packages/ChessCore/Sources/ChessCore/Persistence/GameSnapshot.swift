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
public struct GameSnapshot: Codable, Sendable, Equatable {
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

    public init(id: UUID, date: Date, botId: String, userColor: Piece.Color, mode: PlayMode,
                startFen: String, moves: [String], sans: [String], result: GameResult,
                verdicts: [Verdict], analysisVersion: Int, playerRatingUsed: Int) {
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

public func encodeSnapshot(_ snapshot: GameSnapshot) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(snapshot)
}

public func decodeSnapshot(_ data: Data) throws -> GameSnapshot {
    let decoder = JSONDecoder()
    return try decoder.decode(GameSnapshot.self, from: data)
}
