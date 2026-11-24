import Foundation
import SwiftData
import ChessCore

// CloudKit-compatible like GameRecord: every stored property has a default, nothing is unique.
// One row each is expected; sync duplicates are merged on read (latest `updated` wins).

/// Who the user is to the coach: platform account, rating and goal.
@Model
final class UserProfile {
    /// "chesscom", "lichess" or "" (new player).
    var platform: String = ""
    var username: String = ""
    var avatarURL: String?
    var currentRating: Int = PlayerProfile.defaultRating
    var goalRating: Int?
    var goalDate: Date?
    var updated: Date = Date.now

    init(platform: String = "", username: String = "", avatarURL: String? = nil,
         currentRating: Int = PlayerProfile.defaultRating) {
        self.platform = platform
        self.username = username
        self.avatarURL = avatarURL
        self.currentRating = currentRating
    }

    var importPlatform: ImportPlatform? { ImportPlatform(rawValue: platform) }
    var tier: RatingTier { RatingTier(rating: currentRating) }
}

/// The current week of training, stored as JSON so the plan format can grow.
@Model
final class TrainingPlanRecord {
    var planData: Data = Data()
    var created: Date = Date.now

    init(plan: TrainingPlan) throws {
        planData = try JSONEncoder().encode(plan)
        created = plan.created
    }

    var plan: TrainingPlan? { try? JSONDecoder().decode(TrainingPlan.self, from: planData) }
}

/// Reads and writes the profile, plan and imported games. Main context only.
@MainActor
enum ProfileStore {
    static func profile(in context: ModelContext) -> UserProfile? {
        let rows = (try? context.fetch(FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.updated, order: .reverse)]))) ?? []
        return rows.first
    }

    static func plan(in context: ModelContext) -> TrainingPlan? {
        let rows = (try? context.fetch(FetchDescriptor<TrainingPlanRecord>(sortBy: [SortDescriptor(\.created, order: .reverse)]))) ?? []
        return rows.first?.plan
    }

    /// Replaces the profile (one row).
    @discardableResult
    static func saveProfile(platform: ImportPlatform?, username: String, avatarURL: URL?, rating: Int,
                            in context: ModelContext) -> UserProfile {
        let existing = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        let row = existing.first ?? {
            let p = UserProfile()
            context.insert(p)
            return p
        }()
        for extra in existing.dropFirst() { context.delete(extra) }
        row.platform = platform?.rawValue ?? ""
        row.username = username
        row.avatarURL = avatarURL?.absoluteString
        row.currentRating = rating
        row.updated = .now
        context.saveReporting("your profile")
        return row
    }

    static func saveGoal(rating: Int, months: Int, in context: ModelContext, now: Date = .now) {
        guard let row = profile(in: context) else { return }
        row.goalRating = rating
        row.goalDate = Calendar.current.date(byAdding: .month, value: months, to: now)
        row.updated = now
        context.saveReporting("your goal")
    }

    /// Replaces any previous plan.
    static func savePlan(_ plan: TrainingPlan, in context: ModelContext) {
        for row in (try? context.fetch(FetchDescriptor<TrainingPlanRecord>())) ?? [] { context.delete(row) }
        if let record = try? TrainingPlanRecord(plan: plan) { context.insert(record) }
        context.saveReporting("your plan")
    }

    /// Stores imported games. A game already stored (same stable id) is updated in place,
    /// keeping its analysis when that is a full one (or the import brings none), so a
    /// re-import doesn't throw away minutes of engine work or churn CloudKit with
    /// delete-plus-insert. Extra copies of a game left by sync are removed.
    static func saveGames(_ games: [GameSnapshot], in context: ModelContext) {
        let ids = Set(games.map(\.id))
        let rows = (try? context.fetch(FetchDescriptor<GameRecord>(predicate: #Predicate { ids.contains($0.id) },
                                                                  sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let kept = GameRecord.unique(rows)
        let keptIDs = Set(kept.map(ObjectIdentifier.init))
        for extra in rows where !keptIDs.contains(ObjectIdentifier(extra)) { context.delete(extra) }
        let existing = Dictionary(kept.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for game in games {
            guard let row = existing[game.id] else {
                if let record = try? GameRecord(snapshot: game) { context.insert(record) }
                continue
            }
            var merged = game
            if let stored = row.snapshot {
                if let analysis = stored.analysis, analysis.isFull || merged.analysis == nil {
                    merged.analysis = analysis
                }
                merged.openingName = merged.openingName ?? stored.openingName
            }
            try? row.update(merged)
        }
        context.saveReporting("your imported games")
    }
}
