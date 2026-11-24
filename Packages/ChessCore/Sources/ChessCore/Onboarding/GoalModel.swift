import Foundation

/// Rating distribution of active players on one platform, and the goal-chance heuristic.
///
/// SOURCE (approximation, not official data): the anchor points below are hand-read from
/// publicly shared rating-distribution charts - chess.com rapid (chess.com's leaderboard and
/// member-stats pages, community-posted histograms, 2024-2025) and Lichess blitz (lichess.org/stat/
/// rating/distribution/blitz, 2025). They are rounded to whole percent and smoothed by monotone
/// interpolation into 50-point buckets. Good enough for "top N %" and a picture; the UI says
/// "approximate, active players". Replace with a fresh export when the app ships.
public struct RatingDistribution: Sendable {
    public static let bucketWidth = 50
    public static let range = 100...3000

    /// (rating, % of active players below it), increasing.
    public let anchors: [(rating: Int, below: Double)]

    public static let chesscom = RatingDistribution(anchors: [
        (100, 0), (200, 4), (300, 11), (400, 21), (500, 32), (600, 43), (700, 53), (800, 62),
        (900, 70), (1000, 76.5), (1100, 81.5), (1200, 85.5), (1300, 88.7), (1400, 91.3),
        (1500, 93.4), (1600, 95.1), (1700, 96.4), (1800, 97.4), (1900, 98.2), (2000, 98.8),
        (2200, 99.5), (2400, 99.82), (2600, 99.95), (3000, 100),
    ])

    public static let lichess = RatingDistribution(anchors: [
        (100, 0), (600, 0.6), (800, 2.5), (1000, 7), (1100, 10.5), (1200, 15), (1300, 21),
        (1400, 28), (1500, 36), (1600, 45), (1700, 54), (1800, 63), (1900, 71), (2000, 78),
        (2100, 84), (2200, 89), (2300, 92.8), (2400, 95.6), (2500, 97.5), (2600, 98.7),
        (2800, 99.7), (3000, 100),
    ])

    public static func forPlatform(_ platform: ImportPlatform?) -> RatingDistribution {
        platform == .lichess ? .lichess : .chesscom
    }

    /// Percent of active players below `rating` (0…100), linear between anchors.
    public func below(_ rating: Int) -> Double {
        guard let first = anchors.first, let last = anchors.last else { return 50 }
        if rating <= first.rating { return first.below }
        if rating >= last.rating { return last.below }
        let i = anchors.firstIndex { $0.rating >= rating }!
        let a = anchors[i - 1], b = anchors[i]
        let t = Double(rating - a.rating) / Double(b.rating - a.rating)
        return a.below + t * (b.below - a.below)
    }

    /// "Top N %" for a rating: share of players at or above it, at least 0.1.
    public func topPercent(_ rating: Int) -> Double {
        max(0.1, 100 - below(rating))
    }

    /// Share of players (percent) in each 50-point bucket starting at `range.lowerBound`.
    public var buckets: [(rating: Int, share: Double)] {
        stride(from: Self.range.lowerBound, to: Self.range.upperBound, by: Self.bucketWidth).map { r in
            (r, below(r + Self.bucketWidth) - below(r))
        }
    }
}

/// The goal-chance heuristic (plan4 spec, "Goal-rating picker").
public enum GoalModel {
    public static let periods = [1, 3, 6, 12]

    /// Expected monthly gain with daily practice: ~70·e^(−(r−600)/1100), falling as rating rises.
    public static func monthlyGain(at rating: Double) -> Double {
        70 * exp(-(rating - 600) / 1100)
    }

    /// Expected total gain over `months`, month by month (the gain slows as the rating climbs).
    public static func expectedGain(from rating: Int, months: Int) -> Double {
        var r = Double(rating)
        for _ in 0..<max(0, months) { r += monthlyGain(at: r) }
        return r - Double(rating)
    }

    /// Estimated chance (percent, clamped 3…97) of reaching `target` from `current` in `months`:
    /// Φ((expected − needed) / σ), σ = 40 % of expected.
    public static func chance(current: Int, target: Int, months: Int) -> Int {
        let needed = Double(target - current)
        let expected = expectedGain(from: current, months: months)
        let sigma = max(1, 0.4 * expected)
        let p = phi((expected - needed) / sigma) * 100
        return Int(min(97, max(3, p.rounded())))
    }

    /// Standard normal CDF.
    static func phi(_ z: Double) -> Double {
        0.5 * (1 + erf(z / 2.squareRoot()))
    }

    /// A sensible default target: the rating expected after `months`, rounded up to 50.
    public static func suggestedTarget(current: Int, months: Int = 3) -> Int {
        let raw = Double(current) + expectedGain(from: current, months: months)
        return Int((raw / 50).rounded(.up)) * 50
    }

    /// Rating points the goal picker shows at once.
    public static let pickerSpan = 1500

    /// The goal picker's range: from 300 below `current`, kept inside the distribution
    /// (`RatingDistribution.range`) unless the player is near or above its top, where it
    /// reaches past `current` so a goal above today's rating can always be picked.
    public static func pickerWindow(current: Int) -> ClosedRange<Int> {
        let base = roundDown(current)
        let range = RatingDistribution.range
        var lo = max(range.lowerBound, base - 300)
        if lo + pickerSpan > range.upperBound {
            let hi = max(range.upperBound, base + 150)
            lo = hi - pickerSpan
        }
        return lo...(lo + pickerSpan)
    }

    /// The lowest goal the picker allows: the next 50 above today's rating.
    public static func minimumTarget(current: Int) -> Int {
        roundDown(current) + 50
    }

    /// A picked goal kept above today's rating and inside the picker.
    public static func clampTarget(_ target: Int, current: Int) -> Int {
        min(max(target, minimumTarget(current: current)), pickerWindow(current: current).upperBound)
    }

    private static func roundDown(_ rating: Int) -> Int {
        rating / RatingDistribution.bucketWidth * RatingDistribution.bucketWidth
    }

    /// The honest line above "Practice daily with Chess Coach and you can do it."
    public static func verdict(chance: Int, months: Int) -> String {
        let span = months == 1 ? "a month" : "\(months) months"
        switch chance {
        case ..<25: return "Ambitious. About \(chance) in 100 players who practise daily get there in \(span)."
        case ..<60: return "A real stretch. About \(chance) in 100 who practise daily make it in \(span)."
        default: return "Very doable. Most players who practise daily get there in \(span)."
        }
    }
}
