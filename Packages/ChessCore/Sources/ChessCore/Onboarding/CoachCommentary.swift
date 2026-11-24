import Foundation

/// The coach character's mood; the app maps it to a pose image.
public enum CoachMood: String, Sendable, CaseIterable, Codable {
    case neutral, pleased, thinking, concerned
}

/// One thing the coach says. `text` may contain square chips written `[e4]`.
public struct CoachLine: Sendable, Equatable {
    public var mood: CoachMood
    public var text: String

    public init(_ mood: CoachMood, _ text: String) {
        self.mood = mood
        self.text = text
    }
}

/// What the coach says while onboarding reads the user's games. Plain rules, no LLM.
public enum CoachCommentary {
    public static func fetching(platform: ImportPlatform, count: Int) -> CoachLine {
        CoachLine(.neutral, "Pulling your last \(count) games from \(platform.title). I'll read every move.")
    }

    public static func analysing(index: Int, total: Int, opponent: String?) -> CoachLine {
        let who = opponent.map { " against \($0)" } ?? ""
        return CoachLine(.thinking, "Game \(index + 1) of \(total)\(who). Looking…")
    }

    /// The remark after game `index` is analysed: the costliest mistake with its square, or praise.
    public static func afterGame(index: Int, snapshot: GameSnapshot) -> CoachLine {
        let n = index + 1
        let summary = GameSummary(snapshot)
        let tail = summary.won == true ? " You won anyway." : ""
        guard let worst = summary.worst else {
            if let acc = summary.accuracy, acc >= 85 {
                return CoachLine(.pleased, "Game \(n): \(Int(acc.rounded())) accuracy, no real mistakes. Sharp.")
            }
            return CoachLine(.pleased, "Game \(n): no blunders. Nice and tidy.")
        }
        let move = worst.facts.moveNumber
        let to = String(worst.uci.dropFirst(2).prefix(2))
        let bestTo = String(worst.bestMove.dropFirst(2).prefix(2))
        let piece = pieceName(at: String(worst.uci.prefix(2)), fen: worst.facts.fenBefore)

        if worst.motifs.contains(.hangingPiece), let piece {
            return CoachLine(.concerned, "Game \(n): your \(piece) on [\(to)] was left hanging on move \(move). Noted.\(tail)")
        }
        if worst.motifs.contains(.allowedFork) {
            return CoachLine(.concerned, "Game \(n): move \(move) walked into a fork. We'll fix that one.\(tail)")
        }
        if worst.motifs.contains(.missedMate), bestTo.count == 2 {
            return CoachLine(.thinking, "Game \(n): mate was there on move \(move), starting on [\(bestTo)]. You'll see it next time.")
        }
        if worst.motifs.contains(.allowedMate) {
            return CoachLine(.concerned, "Game \(n): move \(move) let a mate through. Noted.")
        }
        if worst.motifs.contains(.missedCapture), bestTo.count == 2 {
            return CoachLine(.thinking, "Game \(n): free material on [\(bestTo)] at move \(move). Take it next time.\(tail)")
        }
        if worst.motifs.contains(.openingPrinciple) {
            return CoachLine(.thinking, "Game \(n): queen out on move \(move). Develop first, queen later.\(tail)")
        }
        let label = worst.classification.label.lowercased()
        return CoachLine(.thinking, "Game \(n): a \(label) on move \(move), [\(to)]. Noted.\(tail)")
    }

    public static func done(report: WeaknessReport) -> CoachLine {
        guard let top = report.weaknesses.first else {
            return CoachLine(.pleased, "Done. \(report.gamesAnalysed) games, and nothing keeps repeating. Let's see where you stand.")
        }
        return CoachLine(.thinking, "Done. One thing keeps coming back: \(top.motif.habit.lowercasedFirst), \(top.count) times in \(report.gamesAnalysed) games.")
    }

    static func pieceName(at square: String, fen: String) -> String? {
        guard square.count == 2, let piece = Rules.piece(at: Square(square), fen: fen) else { return nil }
        switch piece.kind {
        case .pawn: return "pawn"
        case .knight: return "knight"
        case .bishop: return "bishop"
        case .rook: return "rook"
        case .queen: return "queen"
        case .king: return "king"
        }
    }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
