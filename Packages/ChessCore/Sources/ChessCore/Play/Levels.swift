import Foundation

/// How the engine picks a bot's move for a target rating.
public enum BotStyle: Equatable, Sendable {
    /// Full strength to a fixed depth (lesson opponents, ratings above the ladder).
    case full(depth: Int)
    /// Stockfish's own calibrated limit (`UCI_LimitStrength` + `UCI_Elo`, CCRL Blitz scale).
    case limited(uciElo: Int, movetimeMs: Int)
    /// Below anything Stockfish plays by itself (its lowest `UCI_Elo` is 1320): the app picks
    /// among the engine's top lines (`pickHumanlikeMove`).
    case humanlike(HumanlikeStyle)
}

public struct HumanlikeStyle: Equatable, Sendable {
    /// Search depth of the full-strength pass that scores the candidate moves.
    public var depth: Int
    /// Candidate moves scored by that pass.
    public var multiPV: Int
    /// Softmax temperature over the candidates' centipawn loss: higher plays worse moves.
    public var temperatureCp: Double
    /// Chance of a random legal move instead (a hung piece, a missed threat).
    public var blunderChance: Double

    public init(depth: Int, multiPV: Int, temperatureCp: Double, blunderChance: Double) {
        self.depth = depth
        self.multiPV = multiPV
        self.temperatureCp = temperatureCp
        self.blunderChance = blunderChance
    }
}

/// The numbers behind `botStyle`. Built-in values ship in the app; `BotTuning.current` can be
/// replaced at run time by a downloaded copy (`BotTuningSync` in the app), so strength can be
/// tuned without a new build. Every value is clamped by `sanitized()` before use.
public struct BotTuning: Codable, Equatable, Sendable {
    public struct Anchor: Codable, Equatable, Sendable {
        public var elo: Int
        public var temperatureCp: Double
        public var blunderChance: Double

        public init(elo: Int, temperatureCp: Double, blunderChance: Double) {
            self.elo = elo
            self.temperatureCp = temperatureCp
            self.blunderChance = blunderChance
        }
    }

    /// Ratings below this use the humanlike picker; from it up, Stockfish's own limit.
    public var humanlikeBelow: Int
    /// Subtracted from a bot's rating to get `UCI_Elo`: engine Elo (CCRL Blitz, engine
    /// opponents) plays stronger than the same human online rating.
    public var uciEloOffset: Int
    public var limitedMovetimeMs: Int
    /// Ratings from this up play at full strength (lesson opponents use 3000).
    public var fullFrom: Int
    public var fullDepth: Int
    public var humanlikeDepth: Int
    public var humanlikeMultiPV: Int
    /// Temperature and blunder chance by rating, interpolated linearly between anchors.
    public var anchors: [Anchor]

    public init(humanlikeBelow: Int, uciEloOffset: Int, limitedMovetimeMs: Int, fullFrom: Int,
                fullDepth: Int, humanlikeDepth: Int, humanlikeMultiPV: Int, anchors: [Anchor]) {
        self.humanlikeBelow = humanlikeBelow
        self.uciEloOffset = uciEloOffset
        self.limitedMovetimeMs = limitedMovetimeMs
        self.fullFrom = fullFrom
        self.fullDepth = fullDepth
        self.humanlikeDepth = humanlikeDepth
        self.humanlikeMultiPV = humanlikeMultiPV
        self.anchors = anchors
    }

    public static let builtIn = BotTuning(
        humanlikeBelow: 1500, uciEloOffset: 200, limitedMovetimeMs: 800,
        fullFrom: 2500, fullDepth: 15, humanlikeDepth: 8, humanlikeMultiPV: 12,
        // From two BotCalibration runs, aimed at human ACPL for each rating (docs/reference/
        // engine-measurements.md). Keep in step with gh-pages config/bots.json.
        anchors: [
            Anchor(elo: 600, temperatureCp: 250, blunderChance: 0.21),
            Anchor(elo: 800, temperatureCp: 190, blunderChance: 0.14),
            Anchor(elo: 1000, temperatureCp: 135, blunderChance: 0.08),
            Anchor(elo: 1300, temperatureCp: 80, blunderChance: 0.035),
            Anchor(elo: 1500, temperatureCp: 60, blunderChance: 0.02),
        ])

    /// Every value inside safe bounds, anchors sorted; no anchors falls back to the built-in ones.
    public func sanitized() -> BotTuning {
        func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }
        let cleanAnchors = anchors
            .filter { $0.temperatureCp.isFinite && $0.blunderChance.isFinite }
            .map { Anchor(elo: clamp($0.elo, 0, 4000), temperatureCp: clamp($0.temperatureCp, 1, 1000),
                          blunderChance: clamp($0.blunderChance, 0, 0.5)) }
            .sorted { $0.elo < $1.elo }
        return BotTuning(
            humanlikeBelow: clamp(humanlikeBelow, 0, 4000),
            uciEloOffset: clamp(uciEloOffset, -500, 1000),
            limitedMovetimeMs: clamp(limitedMovetimeMs, 100, 5000),
            fullFrom: clamp(fullFrom, 1500, 4000),
            fullDepth: clamp(fullDepth, 4, 22),
            humanlikeDepth: clamp(humanlikeDepth, 1, 16),
            humanlikeMultiPV: clamp(humanlikeMultiPV, 2, 20),
            anchors: cleanAnchors.isEmpty ? BotTuning.builtIn.anchors : cleanAnchors)
    }

    /// The tuning bots use now. Starts as `builtIn`; the app swaps in a downloaded copy.
    public static var current: BotTuning {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue.sanitized() } }
    }

    private static let storage = LockedValue(BotTuning.builtIn)
}

/// The style a bot of `elo` plays with under `tuning`.
public func botStyle(elo: Int, tuning: BotTuning = .current) -> BotStyle {
    if elo >= tuning.fullFrom { return .full(depth: tuning.fullDepth) }
    if elo >= tuning.humanlikeBelow {
        let lowest = 1320, highest = 3190  // Stockfish's UCI_Elo range
        return .limited(uciElo: min(max(elo - tuning.uciEloOffset, lowest), highest),
                        movetimeMs: tuning.limitedMovetimeMs)
    }
    let anchors = tuning.anchors
    let temperature: Double, blunder: Double
    if let first = anchors.first, elo <= first.elo {
        (temperature, blunder) = (first.temperatureCp, first.blunderChance)
    } else if let last = anchors.last, elo >= last.elo {
        (temperature, blunder) = (last.temperatureCp, last.blunderChance)
    } else if let i = anchors.firstIndex(where: { $0.elo >= elo }), i > 0 {
        let a = anchors[i - 1], b = anchors[i]
        let t = Double(elo - a.elo) / Double(max(b.elo - a.elo, 1))
        temperature = a.temperatureCp + (b.temperatureCp - a.temperatureCp) * t
        blunder = a.blunderChance + (b.blunderChance - a.blunderChance) * t
    } else {
        (temperature, blunder) = (100, 0.05)  // unreachable: sanitized tunings have anchors
    }
    return .humanlike(HumanlikeStyle(depth: tuning.humanlikeDepth, multiPV: tuning.humanlikeMultiPV,
                                     temperatureCp: temperature, blunderChance: blunder))
}

/// A humanlike bot's move: usually one of the engine's top lines, weighted by
/// `exp(-cpLoss / temperature)`, sometimes (`blunderChance`) a random legal move. `lines` are
/// scored from the side to move. Falls back to a random legal move when no line is usable.
public func pickHumanlikeMove<R: RandomNumberGenerator>(
    lines: [PVLine], legalMoves: [String], style: HumanlikeStyle, using rng: inout R
) -> String {
    let candidates: [(move: String, cp: Double)] = lines.compactMap { line in
        guard let move = line.pv.first, legalMoves.contains(move) else { return nil }
        return (move, toCp(line.score, sideToMove: .white))
    }
    guard let best = candidates.max(by: { $0.cp < $1.cp }) else {
        return legalMoves.randomElement(using: &rng) ?? ""
    }
    if legalMoves.count > 1, Double.random(in: 0..<1, using: &rng) < style.blunderChance {
        return legalMoves.filter { $0 != best.move }.randomElement(using: &rng) ?? best.move
    }
    let temperature = max(style.temperatureCp, 1)
    let weights = candidates.map { exp(-(best.cp - $0.cp) / temperature) }
    var roll = Double.random(in: 0..<weights.reduce(0, +), using: &rng)
    for (candidate, weight) in zip(candidates, weights) {
        if roll < weight { return candidate.move }
        roll -= weight
    }
    return best.move
}

/// A value behind a lock, for small shared settings read from any thread.
final class LockedValue<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
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
