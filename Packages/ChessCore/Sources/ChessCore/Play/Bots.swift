import Foundation

/// A named sparring partner with a fixed strength.
public struct Bot: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let elo: Int
    public let blurb: String

    public var avatarAsset: String { "Bots/\(id)" }

    public init(id: String, name: String, elo: Int, blurb: String) {
        self.id = id
        self.name = name
        self.elo = elo
        self.blurb = blurb
    }

    public static let all: [Bot] = [
        Bot(id: "pip", name: "Pip", elo: 600,
            blurb: "Just learning — will hang pieces right alongside you."),
        Bot(id: "ron", name: "Rookie Ron", elo: 800,
            blurb: "Knows the rules but misses most tactics."),
        Bot(id: "cadet", name: "Cadet", elo: 1000,
            blurb: "Solid basics. Punishes obvious blunders."),
        Bot(id: "blaze", name: "Blaze", elo: 1300,
            blurb: "Aggressive attacker — keep your king safe."),
        Bot(id: "wall", name: "The Wall", elo: 1600,
            blurb: "Patient and defensive. Hard to break down."),
        Bot(id: "maestro", name: "Maestro", elo: 1900,
            blurb: "Strong positional understanding."),
        Bot(id: "vera", name: "Vera", elo: 2100,
            blurb: "Sharp, precise, and quick to pounce."),
        Bot(id: "apex", name: "Apex", elo: 2300,
            blurb: "Full strength. Good luck."),
    ]
}
