import Foundation

/// How thoroughly a stored analysis was made.
public enum AnalysisPass: String, Codable, Sendable, Equatable {
    /// Node-limited search, book plies skipped, capped at a ply limit; or the platform's own
    /// evals. Good enough for the tier, weaknesses and plan; Review re-analyses it at full depth.
    case quick
    /// The review-grade search (bulk depth, MultiPV 2, every ply).
    case full
}

/// Full-game analysis stored inside a saved game (GameSnapshot).
public struct GameAnalysis: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var depth: Int
    /// One verdict per ply, both colours, in ply order. A quick pass may stop early
    /// (`AnalysisPlan.quickMaxPly`), so it can hold fewer verdicts than the game has moves.
    public var verdicts: [Verdict]
    /// White win percentage per position; count is verdicts + 1.
    public var whiteWin: [Double]
    public var accuracyWhite: Double
    public var accuracyBlack: Double
    /// Quick or full. Data stored before the field existed was full-depth: `.full`.
    public var pass: AnalysisPass
    /// Nil when this app's engine searched it; "lichess" when built from Lichess's own evals.
    public var evalSource: String?
    /// The node limit of a quick pass.
    public var nodes: Int?

    public init(version: Int = GameAnalysis.currentVersion, depth: Int, verdicts: [Verdict],
                whiteWin: [Double], accuracyWhite: Double, accuracyBlack: Double,
                pass: AnalysisPass = .full, evalSource: String? = nil, nodes: Int? = nil) {
        self.version = version
        self.depth = depth
        self.verdicts = verdicts
        self.whiteWin = whiteWin
        self.accuracyWhite = accuracyWhite
        self.accuracyBlack = accuracyBlack
        self.pass = pass
        self.evalSource = evalSource
        self.nodes = nodes
    }

    /// Review-grade: every ply searched at the bulk depth by this app's engine.
    public var isFull: Bool { pass == .full }
}

extension GameAnalysis {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        depth = try c.decode(Int.self, forKey: .depth)
        verdicts = try c.decode([Verdict].self, forKey: .verdicts)
        whiteWin = try c.decode([Double].self, forKey: .whiteWin)
        accuracyWhite = try c.decode(Double.self, forKey: .accuracyWhite)
        accuracyBlack = try c.decode(Double.self, forKey: .accuracyBlack)
        // Missing: written before quick passes existed, so full. Unknown (a later pass kind):
        // not trusted as full, so it gets re-analysed.
        if let raw = try? c.decodeIfPresent(String.self, forKey: .pass) {
            pass = AnalysisPass(rawValue: raw) ?? .quick
        } else {
            pass = .full
        }
        evalSource = try? c.decodeIfPresent(String.self, forKey: .evalSource)
        nodes = try? c.decodeIfPresent(Int.self, forKey: .nodes)
    }
}
