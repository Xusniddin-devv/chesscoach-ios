import Testing
import SwiftData
import Foundation
import ChessCore
@testable import ChessCoach

/// Profile/plan persistence and the onboarding model, with a fixture client (no network).
@MainActor
struct OnboardingTests {
    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: ModelStore.schema,
            configurations: ModelConfiguration(schema: ModelStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return container.mainContext
    }

    private func snapshot(_ id: UUID = UUID()) -> GameSnapshot {
        GameSnapshot(id: id, date: .now, botId: "chesscom", userColor: .white, mode: .silent, startFen: Rules.startFen,
                     moves: ["e2e4"], sans: ["e4"], result: .whiteWins, verdicts: [], analysisVersion: 1,
                     playerRatingUsed: 950, source: "chesscom", opponentName: "opp", opponentRating: 990)
    }

    @Test func profileGoalPlanAndGamesPersist() throws {
        let ctx = try context()
        ProfileStore.saveProfile(platform: .chesscom, username: "me", avatarURL: nil, rating: 940, in: ctx)
        ProfileStore.saveProfile(platform: .lichess, username: "me2", avatarURL: URL(string: "https://a/b.png"), rating: 1500, in: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<UserProfile>()) == 1)
        let profile = try #require(ProfileStore.profile(in: ctx))
        #expect(profile.importPlatform == .lichess && profile.currentRating == 1500 && profile.tier == .rook)

        ProfileStore.saveGoal(rating: 1700, months: 6, in: ctx)
        #expect(profile.goalRating == 1700 && profile.goalDate != nil)

        let plan = TrainingPlan.make(weaknesses: [.allowedFork], rating: 1500, ownMistakes: 0)
        ProfileStore.savePlan(plan, in: ctx)
        ProfileStore.savePlan(plan, in: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<TrainingPlanRecord>()) == 1)
        #expect(ProfileStore.plan(in: ctx) == plan)

        // Re-importing the same platform game replaces it.
        let id = UUID()
        ProfileStore.saveGames([snapshot(id), snapshot()], in: ctx)
        ProfileStore.saveGames([snapshot(id)], in: ctx)
        let games = try ctx.fetch(FetchDescriptor<GameRecord>())
        #expect(games.count == 2)
        #expect(games.compactMap(\.snapshot).allSatisfy(\.isImported))
    }

    @Test func resetClearsOnboardingToo() throws {
        let ctx = try context()
        ProfileStore.saveProfile(platform: nil, username: "", avatarURL: nil, rating: 600, in: ctx)
        UserDefaults.standard.set(true, forKey: Pref.hasOnboarded)
        try DataReset.run(in: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<UserProfile>()) == 0)
        #expect(!UserDefaults.standard.bool(forKey: Pref.hasOnboarded))
    }

    @Test func usernameCheckFindsAndRejects() async throws {
        let model = OnboardingModel()
        model.makeClient = { _ in FakeClient() }
        model.choose(.chesscom)
        model.username = "hikaru"
        model.usernameChanged()
        try await waitUntil { model.foundProfile != nil }
        #expect(model.foundProfile?.currentRating == 1234)
        model.username = "ghost"
        model.usernameChanged()
        try await waitUntil { model.lookup == .notFound }
    }

    @Test func newPlayerPathEstimatesAndPlans() throws {
        let ctx = try context()
        let model = OnboardingModel()
        model.choose(nil)
        model.answer(0, 1)
        model.answer(1, 2)
        model.answer(2, 2)
        #expect(model.step == .reveal)
        #expect(model.rating == 800)
        #expect(model.target % 50 == 0 && model.target > 800)
        model.buildPlan(completedLessons: [])
        #expect(model.plan?.focus.first == .missedMate)
        model.save(in: ctx)
        #expect(ProfileStore.profile(in: ctx)?.currentRating == 800)
        #expect(ProfileStore.plan(in: ctx) != nil)
        #expect(UserDefaults.standard.bool(forKey: Pref.hasOnboarded))
        UserDefaults.standard.removeObject(forKey: Pref.hasOnboarded)
    }

    @Test func coachTextChipsParse() {
        #expect(CoachText.segments("on [c4] and [f7].") == [.words("on "), .square("c4"), .words(" and "), .square("f7"), .words(".")])
        #expect(CoachText.segments("[x9] stays text") == [.words("[x9] stays text")])
        #expect(CoachText.plain("**Hi** [e4]") == "Hi e4")
        #expect(SquareChip.isLight("h1") && !SquareChip.isLight("a1"))
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(30)) }
        #expect(condition())
    }
}

private struct FakeClient: GameImportClient {
    var platform: ImportPlatform { .chesscom }
    func profile(_ username: String) async throws -> PlatformProfile {
        guard username == "hikaru" else { throw ImportError.userNotFound }
        return PlatformProfile(platform: .chesscom, username: "Hikaru", ratings: ["rapid": 1234])
    }
    func recentGames(_ username: String, limit: Int, progress: @Sendable (Int) -> Void) async throws -> [String] { [] }
}
