import Foundation

public struct Score: Sendable, Equatable, Codable {
    public var cp: Int?
    public var mate: Int?

    public init(cp: Int? = nil, mate: Int? = nil) {
        self.cp = cp
        self.mate = mate
    }
}

public struct PVLine: Sendable, Equatable, Codable {
    public var multipv: Int
    public var depth: Int
    public var score: Score
    public var pv: [String]

    public init(multipv: Int, depth: Int, score: Score, pv: [String]) {
        self.multipv = multipv
        self.depth = depth
        self.score = score
        self.pv = pv
    }
}

public struct AnalysisResult: Sendable, Equatable, Codable {
    /// UCI best move; empty string when there is none.
    public var bestMove: String
    public var lines: [PVLine]

    public init(bestMove: String, lines: [PVLine]) {
        self.bestMove = bestMove
        self.lines = lines
    }
}

public struct AnalysisRequest: Sendable, Equatable, Codable, Hashable {
    public var startFen: String
    public var moves: [String]
    public var depth: Int
    public var multiPV: Int

    public init(startFen: String, moves: [String], depth: Int, multiPV: Int) {
        self.startFen = startFen
        self.moves = moves
        self.depth = depth
        self.multiPV = multiPV
    }

    public var cacheKey: String {
        "\(depth)|\(startFen)|\(moves.joined(separator: " "))"
    }
}

public protocol ChessEngine: Sendable {
    func analyze(_ request: AnalysisRequest) async throws -> AnalysisResult
    /// Returns a UCI move, or "" when there is none.
    func opponentMove(startFen: String, moves: [String], elo: Int) async throws -> String
}
