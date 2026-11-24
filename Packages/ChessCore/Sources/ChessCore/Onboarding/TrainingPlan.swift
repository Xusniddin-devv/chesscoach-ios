import Foundation

/// One thing to do on a plan day.
public struct PlanTask: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// Bank puzzles on a weakness (`puzzleIds`).
        case puzzles
        /// Puzzles made from the user's own mistakes (built at launch; `count` of them).
        case ownMistakes
        /// A Learn lesson (`lessonId`).
        case lesson
        /// A game against a bot (`botId`), Training mode.
        case play
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String
    public var puzzleIds: [String]
    public var count: Int
    public var lessonId: String?
    public var botId: String?
    public var motif: Motif?

    public init(id: String, kind: Kind, title: String, detail: String, puzzleIds: [String] = [],
                count: Int = 0, lessonId: String? = nil, botId: String? = nil, motif: Motif? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.puzzleIds = puzzleIds
        self.count = count
        self.lessonId = lessonId
        self.botId = botId
        self.motif = motif
    }
}

public struct PlanDay: Codable, Sendable, Equatable, Identifiable {
    /// 0…6.
    public var index: Int
    /// The day's theme: "Undefended pieces".
    public var focus: String
    public var tasks: [PlanTask]
    public var id: Int { index }
}

/// A week of training built from the user's weaknesses (or onboarding answers).
/// How often the player plays (the coach asks during the import). It sizes each day's tasks.
public enum PlayFrequency: String, Codable, Sendable, CaseIterable {
    case daily, fewTimesAWeek, weekends

    public var title: String {
        switch self {
        case .daily: "Daily"
        case .fewTimesAWeek: "Few times a week"
        case .weekends: "Weekends"
        }
    }

    /// Puzzles per puzzle task (and own mistakes per review).
    public var puzzlesPerTask: Int {
        switch self {
        case .daily: 8
        case .fewTimesAWeek: TrainingPlan.puzzlesPerTask
        case .weekends: 3
        }
    }
}

public struct TrainingPlan: Codable, Sendable, Equatable {
    public static let length = 7
    public static let puzzlesPerTask = 5

    public var created: Date
    public var rating: Int
    public var focus: [Motif]
    public var days: [PlanDay]

    /// Day index for `date` (0 on the creation day), or nil after the week.
    public func dayIndex(on date: Date, calendar: Calendar = .current) -> Int? {
        guard !days.isEmpty else { return nil }
        let start = calendar.startOfDay(for: created)
        let day = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0
        return (0..<days.count).contains(day) ? day : (day < 0 ? 0 : nil)
    }

    /// Weaknesses used when the games show fewer than three (or there are no games).
    public static let defaultFocus: [Motif] = [.hangingPiece, .allowedFork, .missedMate]

    /// Builds the week.
    /// - Parameters:
    ///   - weaknesses: most costly first (from `WeaknessReport.top` or onboarding answers).
    ///   - ownMistakes: puzzles available from the user's own games (enables day 1 and 7 reviews).
    ///   - completedLessons: lesson ids already done, skipped where possible.
    ///   - preferredTrack: track for lessons that aren't tied to a weakness (new players' goal).
    public static func make(weaknesses: [Motif], rating: Int, ownMistakes: Int,
                            completedLessons: Set<String> = [], preferredTrack: LessonTrack? = nil,
                            frequency: PlayFrequency = .fewTimesAWeek, now: Date = .now) -> TrainingPlan {
        let puzzlesPerTask = frequency.puzzlesPerTask
        var focus: [Motif] = []
        for m in weaknesses + defaultFocus where !focus.contains(m) { focus.append(m) }
        focus = Array(focus.prefix(3))

        var usedPuzzles: Set<String> = []
        var usedLessons = completedLessons
        let bot = recommendedBot(rating: rating)
        let stretch = Bot.all.first { $0.elo > bot.elo } ?? bot

        func puzzles(_ motif: Motif, day: Int) -> PlanTask {
            let ids = Array(PuzzleBank.forWeakness(motif, rating: rating, excluding: usedPuzzles)
                .prefix(puzzlesPerTask).map(\.id))
            usedPuzzles.formUnion(ids)
            return PlanTask(id: "d\(day)-puzzles-\(motif.rawValue)", kind: .puzzles,
                            title: "\(ids.count) puzzles: \(motif.shortName.lowercased())",
                            detail: puzzleDetail(motif), puzzleIds: ids, count: ids.count, motif: motif)
        }
        func lesson(for motif: Motif?, day: Int, firstOnly: Bool = false) -> PlanTask? {
            let track = motif.map(lessonTrack(for:)) ?? preferredTrack ?? .checkmates
            let pool = LessonLibrary.lessons(in: track)
            // Day 1 stays free: the first lesson of a track is always unlocked.
            let candidates = firstOnly ? Array(pool.prefix(1)) : pool
            guard let l = candidates.first(where: { !usedLessons.contains($0.id) }) ?? (firstOnly ? nil : pool.first)
            else { return nil }
            usedLessons.insert(l.id)
            return PlanTask(id: "d\(day)-lesson-\(l.id)", kind: .lesson, title: l.title,
                            detail: "Lesson · \(track.title)", lessonId: l.id, motif: motif)
        }
        func play(_ b: Bot, day: Int, note: String) -> PlanTask {
            PlanTask(id: "d\(day)-play-\(b.id)", kind: .play, title: "Play \(b.name)",
                     detail: note, botId: b.id)
        }
        func review(day: Int) -> PlanTask {
            PlanTask(id: "d\(day)-own", kind: .ownMistakes, title: "\(min(puzzlesPerTask, ownMistakes)) of your own mistakes",
                     detail: "Find the move you missed", count: min(puzzlesPerTask, ownMistakes))
        }

        let (a, b, c) = (focus[0], focus[1], focus[2])
        var days: [PlanDay] = []
        // Day 1: the most costly habit, own mistakes if we have them, and a free lesson.
        days.append(PlanDay(index: 0, focus: a.shortName, tasks: [
            ownMistakes >= 3 ? review(day: 0) : puzzles(a, day: 0),
            lesson(for: preferredTrack == nil ? a : nil, day: 0, firstOnly: true),
        ].compactMap { $0 }))
        days.append(PlanDay(index: 1, focus: a.shortName, tasks: [
            puzzles(a, day: 1), play(bot, day: 1, note: "Training mode. The coach stops you on a blunder."),
        ]))
        days.append(PlanDay(index: 2, focus: b.shortName, tasks: [puzzles(b, day: 2), lesson(for: b, day: 2)].compactMap { $0 }))
        days.append(PlanDay(index: 3, focus: b.shortName, tasks: [
            puzzles(b, day: 3), play(bot, day: 3, note: "Watch for \(b.shortName.lowercased())."),
        ]))
        days.append(PlanDay(index: 4, focus: c.shortName, tasks: [puzzles(c, day: 4), lesson(for: c, day: 4)].compactMap { $0 }))
        days.append(PlanDay(index: 5, focus: "Mixed", tasks: [
            puzzles(a, day: 5), puzzles(c, day: 5),
        ]))
        days.append(PlanDay(index: 6, focus: "Test day", tasks: [
            ownMistakes >= 3 ? review(day: 6) : puzzles(b, day: 6),
            play(stretch, day: 6, note: "One level up. See what stuck."),
        ]))
        return TrainingPlan(created: now, rating: rating, focus: focus, days: days)
    }

    /// The sparring partner: the strongest bot at or below the rating (at least Pip).
    public static func recommendedBot(rating: Int) -> Bot {
        Bot.all.last { $0.elo <= rating } ?? Bot.all[0]
    }

    /// Which Learn track trains a weakness best.
    public static func lessonTrack(for motif: Motif) -> LessonTrack {
        switch motif {
        case .allowedMate, .missedMate: .checkmates
        case .openingPrinciple: .openings
        // Tactics habits: endgames teach piece coordination and counting.
        case .hangingPiece, .allowedFork, .missedCapture: .endgames
        }
    }

    static func puzzleDetail(_ motif: Motif) -> String {
        switch motif {
        case .hangingPiece: "Spot the piece nobody guards."
        case .allowedFork: "One move, two targets."
        case .missedCapture: "Take what's free, check what's guarded."
        case .allowedMate: "See the mate coming before it lands."
        case .missedMate: "Finish the game when it's there."
        case .openingPrinciple: "Develop first, queen later."
        }
    }
}

/// New players: three tapped answers instead of imported games.
public struct NewPlayerAnswers: Sendable, Equatable {
    public enum Rules: Int, Sendable, CaseIterable { case learning, knowRules, knowTactics }
    public enum Played: Int, Sendable, CaseIterable { case never, few, lots }
    public enum Goal: Int, Sendable, CaseIterable { case winMore, openings, checkmates }

    public var rules: Rules
    public var played: Played
    public var goal: Goal

    public init(rules: Rules, played: Played, goal: Goal) {
        self.rules = rules
        self.played = played
        self.goal = goal
    }

    /// A starting estimate: 400 for someone learning the moves, up to 1000.
    public var estimatedRating: Int {
        400 + rules.rawValue * 200 + played.rawValue * 100
    }

    public var weaknesses: [Motif] {
        switch goal {
        case .winMore: [.hangingPiece, .allowedFork, .missedCapture]
        case .openings: [.openingPrinciple, .hangingPiece, .allowedFork]
        case .checkmates: [.missedMate, .allowedMate, .hangingPiece]
        }
    }

    public var track: LessonTrack {
        switch goal {
        case .winMore: rules == .learning ? .checkmates : .endgames
        case .openings: .openings
        case .checkmates: .checkmates
        }
    }
}
