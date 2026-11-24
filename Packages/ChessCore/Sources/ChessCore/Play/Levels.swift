import Foundation

/// Stockfish-style opponent settings for a target Elo.
public struct LevelSettings: Equatable {
    public let skillLevel: Int
    public let depth: Int

    public init(skillLevel: Int, depth: Int) {
        self.skillLevel = skillLevel
        self.depth = depth
    }
}

/// Maps a target Elo (600...2300, clamped) to engine skill level and search depth.
public func levelSettings(elo: Int) -> LevelSettings {
    let t = strengthFraction(elo: elo)
    return LevelSettings(
        skillLevel: Int((20 * t).rounded()),
        depth: Int((4 + 11 * t).rounded())
    )
}

/// Bot move pacing in milliseconds. `jitter` is expected in [0, 1).
public func thinkTimeMs(elo: Int, jitter: Double) -> Int {
    let t = strengthFraction(elo: elo)
    return Int(((450 + 1250 * t) * (0.7 + 0.6 * jitter)).rounded())
}

private func strengthFraction(elo: Int) -> Double {
    min(max((Double(elo) - 600) / 1700, 0), 1)
}

/// How bad a played move looks in Training mode, from least to most severe.
public enum TrainingSeverity: Comparable, Sendable {
    case good, inaccuracy, mistake, blunder

    private var rank: Int {
        switch self {
        case .good: 0
        case .inaccuracy: 1
        case .mistake: 2
        case .blunder: 3
        }
    }

    public static func < (lhs: TrainingSeverity, rhs: TrainingSeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Classifies a centipawn loss against thresholds that tighten as the player's level rises.
public func trainingSeverity(cpLoss: Int, level: Int) -> TrainingSeverity {
    let thresholds: (inaccuracy: Int, mistake: Int, blunder: Int)
    if level < 1000 {
        thresholds = (120, 250, 450)
    } else if level < 1600 {
        thresholds = (80, 180, 350)
    } else {
        thresholds = (50, 120, 250)
    }
    if cpLoss >= thresholds.blunder { return .blunder }
    if cpLoss >= thresholds.mistake { return .mistake }
    if cpLoss >= thresholds.inaccuracy { return .inaccuracy }
    return .good
}
