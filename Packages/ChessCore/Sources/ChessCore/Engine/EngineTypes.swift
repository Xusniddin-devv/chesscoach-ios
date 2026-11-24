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
    /// Node-limited search (`go nodes N`) instead of `go depth`: the quick onboarding pass.
    /// Nil for every depth search. Optional, so stored requests without it still decode.
    public var nodes: Int?

    public init(startFen: String, moves: [String], depth: Int, multiPV: Int, nodes: Int? = nil) {
        self.startFen = startFen
        self.moves = moves
        self.depth = depth
        self.multiPV = multiPV
        self.nodes = nodes
    }

    public var cacheKey: String {
        let limit = nodes.map { "n\($0)" } ?? "\(depth)"
        return "\(limit)|\(startFen)|\(moves.joined(separator: " "))"
    }
}

/// Thrown by `analyzeInBackground` when a foreground request took the engine over mid-search.
/// The background caller retries the same position later; the partial search is never used.
public struct EngineYielded: Error, Equatable, Sendable {
    public init() {}
}

public protocol ChessEngine: Sendable {
    func analyze(_ request: AnalysisRequest) async throws -> AnalysisResult
    /// Returns a UCI move, or "" when there is none.
    func opponentMove(startFen: String, moves: [String], elo: Int) async throws -> String
    /// Low-priority analysis for the background queue. An engine that can preempt stops this
    /// search as soon as a foreground request arrives and throws `EngineYielded`; the default
    /// is a plain `analyze`.
    func analyzeInBackground(_ request: AnalysisRequest) async throws -> AnalysisResult
}

extension ChessEngine {
    public func analyzeInBackground(_ request: AnalysisRequest) async throws -> AnalysisResult {
        try await analyze(request)
    }
}
