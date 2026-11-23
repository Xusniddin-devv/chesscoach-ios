import Foundation
import SwiftData
import ChessCore

// CloudKit-compatible like GameRecord: every stored property has a default, nothing is
// unique. Two devices can each create a row for the same id before sync; readers merge.

/// Spaced-repetition state of one puzzle, bundled or made from the user's own mistake.
@Model
final class PuzzleProgress {
    var puzzleId: String = ""
    /// "bank" or "blunder".
    var source: String = "bank"
    var intervalDays: Double = 0
    var ease: Double = 2.5
    var reps: Int = 0
    var lapses: Int = 0
    var due: Date = Date.distantPast
    var solvedCount: Int = 0
    var failedCount: Int = 0
    var lastSolved: Date?
    var lastAttempt: Date?

    init(puzzleId: String, source: String) {
        self.puzzleId = puzzleId
        self.source = source
    }

    var srs: SRSState {
        get { SRSState(intervalDays: intervalDays, ease: ease, reps: reps, lapses: lapses) }
        set {
            intervalDays = newValue.intervalDays
            ease = newValue.ease
            reps = newValue.reps
            lapses = newValue.lapses
        }
    }
}

/// A finished lesson.
@Model
final class LessonProgress {
    var lessonId: String = ""
    var completed: Date = Date.now

    init(lessonId: String, completed: Date = .now) {
        self.lessonId = lessonId
        self.completed = completed
    }
}

/// The daily streak (one row; duplicates from sync are merged on read).
@Model
final class StreakState {
    var count: Int = 0
    var lastDay: Date?

    init(count: Int = 0, lastDay: Date? = nil) {
        self.count = count
        self.lastDay = lastDay
    }

    var streak: Streak { Streak(count: count, lastDay: lastDay) }
}

/// Reads and writes training progress. All calls on the main context.
@MainActor
enum TrainingStore {

    // MARK: Streak

    /// The stored streak; with sync duplicates, the most recent one wins.
    static func streak(in context: ModelContext) -> Streak {
        let rows = (try? context.fetch(FetchDescriptor<StreakState>())) ?? []
        return rows.map(\.streak).max { ($0.lastDay ?? .distantPast, $0.count) < ($1.lastDay ?? .distantPast, $1.count) } ?? Streak()
    }

    static func recordActivity(in context: ModelContext, now: Date = .now) {
        let next = streak(in: context).recordingActivity(now: now)
        let rows = (try? context.fetch(FetchDescriptor<StreakState>())) ?? []
        if let row = rows.first {
            row.count = next.count
            row.lastDay = next.lastDay
            rows.dropFirst().forEach(context.delete)
        } else {
            context.insert(StreakState(count: next.count, lastDay: next.lastDay))
        }
        try? context.save()
    }

    // MARK: Puzzles

    static func progress(_ id: String, in context: ModelContext) -> PuzzleProgress? {
        var d = FetchDescriptor<PuzzleProgress>(predicate: #Predicate { $0.puzzleId == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// Records the first outcome of an attempt: schedules the puzzle by SRS (success only
    /// when solved first try without a hint) and counts it.
    static func recordOutcome(puzzleId: String, source: String, clean: Bool, solved: Bool,
                              in context: ModelContext, now: Date = .now) {
        let row = progress(puzzleId, in: context) ?? {
            let p = PuzzleProgress(puzzleId: puzzleId, source: source)
            context.insert(p)
            return p
        }()
        let review = SRS.review(row.srs, success: clean, now: now)
        row.srs = review.state
        row.due = review.due
        row.lastAttempt = now
        if solved { row.solvedCount += 1; row.lastSolved = now } else { row.failedCount += 1 }
        try? context.save()
    }

    /// Marks a later solve in the same attempt (after a retry): counts it, SRS unchanged.
    static func recordLateSolve(puzzleId: String, in context: ModelContext, now: Date = .now) {
        guard let row = progress(puzzleId, in: context) else { return }
        row.solvedCount += 1
        row.lastSolved = now
        try? context.save()
    }

    // MARK: Lessons

    static func completeLesson(_ id: String, in context: ModelContext, now: Date = .now) {
        let existing = (try? context.fetch(FetchDescriptor<LessonProgress>(predicate: #Predicate { $0.lessonId == id }))) ?? []
        if existing.isEmpty { context.insert(LessonProgress(lessonId: id, completed: now)) }
        try? context.save()
    }
}
