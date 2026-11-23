import Foundation

/// Full-game analysis stored inside a saved game (GameSnapshot).
public struct GameAnalysis: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var depth: Int
    /// One verdict per ply, both colours, in ply order.
    public var verdicts: [Verdict]
    /// White win percentage per position; count is moves + 1.
    public var whiteWin: [Double]
    public var accuracyWhite: Double
    public var accuracyBlack: Double

    public init(version: Int = GameAnalysis.currentVersion, depth: Int, verdicts: [Verdict],
                whiteWin: [Double], accuracyWhite: Double, accuracyBlack: Double) {
        self.version = version
        self.depth = depth
        self.verdicts = verdicts
        self.whiteWin = whiteWin
        self.accuracyWhite = accuracyWhite
        self.accuracyBlack = accuracyBlack
    }
}
