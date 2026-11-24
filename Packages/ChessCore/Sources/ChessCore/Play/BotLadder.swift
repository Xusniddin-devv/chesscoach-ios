import Foundation

/// The bots as a sparring ladder: beat a bot to open the next one. The first three
/// (Pip, Rookie Ron, Cadet) are always open; a stronger bot also opens once the player's
/// rating is within `ratingReach` of it, so a strong player is not walled in.
public struct BotLadder: Sendable, Equatable {
    public enum Rung: Sendable, Equatable {
        /// Beaten at least once.
        case beaten(wins: Int)
        /// The first open bot not beaten yet: the one to play.
        case next
        /// Open, not beaten, not next (a later open bot).
        case open
        /// Closed until `requires` is beaten.
        case locked(requires: Bot)
    }

    public static let alwaysOpen = 3
    public static let ratingReach = 100

    public let bots: [Bot]
    public let rungs: [Rung]

    /// - Parameters:
    ///   - wins: wins per bot id, from the saved games.
    ///   - rating: the player's rating estimate, if there is one.
    public init(wins: [String: Int], rating: Int? = nil, bots: [Bot] = Bot.all) {
        self.bots = bots
        var open: [Bool] = []
        for (index, bot) in bots.enumerated() {
            let previousBeaten = index > 0 && (wins[bots[index - 1].id] ?? 0) > 0
            let inReach = rating.map { $0 + Self.ratingReach >= bot.elo } ?? false
            let beaten = (wins[bot.id] ?? 0) > 0
            open.append(index < Self.alwaysOpen || previousBeaten || inReach || beaten)
        }
        let nextIndex = Self.nextIndex(bots: bots, open: open, wins: wins, rating: rating)
        rungs = bots.indices.map { index in
            let count = wins[bots[index].id] ?? 0
            if count > 0 { return .beaten(wins: count) }
            if index == nextIndex { return .next }
            if open[index] { return .open }
            return .locked(requires: bots[index - 1])
        }
    }

    /// A bot this far below the player's rating teaches nothing: it is never the one to play
    /// while a closer bot is open.
    public static let tooEasy = 400

    /// The bot to play: the first open, unbeaten one, skipping bots `tooEasy` below the rating.
    /// A player above every bot's reach gets the strongest bot (nil once it is beaten, so
    /// `next` stays on it).
    private static func nextIndex(bots: [Bot], open: [Bool], wins: [String: Int], rating: Int?) -> Int? {
        let candidates = bots.indices.filter { open[$0] && (wins[bots[$0].id] ?? 0) == 0 }
        guard let rating else { return candidates.first }
        if let fit = candidates.first(where: { bots[$0].elo + tooEasy >= rating }) { return fit }
        guard let strongest = bots.indices.last else { return nil }
        if rating > bots[strongest].elo { return candidates.contains(strongest) ? strongest : nil }
        return candidates.last
    }

    public func rung(for bot: Bot) -> Rung? {
        bots.firstIndex(of: bot).map { rungs[$0] }
    }

    public func isOpen(_ bot: Bot) -> Bool {
        if case .locked = rung(for: bot) { return false }
        return rung(for: bot) != nil
    }

    /// The bot to play next: the first open, unbeaten one; the strongest when all are beaten.
    public var next: Bot? {
        bots.indices.first { rungs[$0] == .next }.map { bots[$0] } ?? bots.last
    }
}
