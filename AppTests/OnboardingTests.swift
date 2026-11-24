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
        return ModelContext(container)
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
        let imported = games.compactMap(\.snapshot).allSatisfy { $0.isImported }
        #expect(imported)
    }

    @Test func resetClearsOnboardingToo() throws {
        let ctx = try context()
        ProfileStore.saveProfile(platform: nil, username: "", avatarURL: nil, rating: 600, in: ctx)
        UserDefaults.standard.set(true, forKey: Pref.hasOnboarded)
        try DataReset.run(in: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<UserProfile>()) == 0)
        #expect(!UserDefaults.standard.bool(forKey: Pref.hasOnboarded))
    }

    @Test func oneNameIsLookedUpOnBothPlatforms() async throws {
        let model = OnboardingModel()
        model.makeClient = { FakeClient(platform: $0) }
        model.go(.find)
        model.username = "hikaru"  // only on chess.com
        model.usernameChanged()
        #expect(model.lookup(.chesscom) == .checking && model.lookup(.lichess) == .checking)
        try await waitUntil { !model.lookups.values.contains(.checking) }
        #expect(model.foundProfiles.map(\.platform) == [.chesscom])
        #expect(model.lookup(.lichess) == .notFound)

        model.username = "both"
        model.usernameChanged()
        try await waitUntil { model.foundProfiles.count == 2 }
        #expect(model.foundProfiles.map(\.platform) == [.chesscom, .lichess])

        model.username = "slow"  // Lichess rate-limits: an inline retry, not an alert
        model.usernameChanged()
        try await waitUntil { !model.lookups.values.contains(.checking) }
        guard case .failed = model.lookup(.lichess) else { Issue.record("expected a failure"); return }
        model.username = ""
        model.usernameChanged()
        #expect(model.lookups.values.allSatisfy { $0 == .idle })
    }

    @Test func importHandsOverAfterQuickReadsAndKeepsAccuraciesReal() async throws {
        let background = BackgroundAnalysis(engine: FakeEngine(botMoves: []), idleDelay: .zero)
        let model = OnboardingModel()
        model.makeClient = { FakeClient(platform: $0) }
        model.setFastEngine = { _ in }
        model.background = background
        model.go(.find)
        let profile = PlatformProfile(platform: .chesscom, username: "hikaru", ratings: ["rapid": 1234])
        model.pick(profile)
        try await waitUntil { model.step == .importing }
        // Two games: the reviewed one has chess.com's accuracy at once, the other none yet.
        try await waitUntil(seconds: 3) { model.slots[0].snapshot != nil }
        #expect(model.slots[0].accuracy == 81.5)
        #expect(model.slots[1].accuracy == nil)
        try await waitUntil(seconds: 12) { model.step == .reveal }
        #expect(model.gamesAnalysed == 2)
        #expect(model.games.allSatisfy { $0.analysis?.pass == .quick })
        #expect(model.slots[1].accuracy != nil)  // filled by the quick read, not estimated
        #expect(model.slots[0].accuracy == 81.5)  // the platform's number stays
        #expect(model.report?.gamesAnalysed == 2)
        #expect(model.rating == 1234)
    }

    @Test func coachAsksHowOftenAndTheAnswerSizesThePlan() async throws {
        let background = BackgroundAnalysis(engine: FakeEngine(botMoves: []), idleDelay: .zero)
        let model = OnboardingModel()
        model.makeClient = { FakeClient(platform: $0) }
        model.setFastEngine = { _ in }
        model.background = background
        model.go(.find)
        model.pick(PlatformProfile(platform: .chesscom, username: "hikaru", ratings: ["rapid": 1234]))
        try await waitUntil(seconds: 12) { model.step == .reveal }
        // Two games are fewer than the question threshold: not asked, the plan uses the default.
        #expect(!model.askingFrequency && model.frequency == nil)
        model.answerFrequency(.weekends)
        model.buildPlan(completedLessons: [])
        let sizes = model.plan?.days.flatMap(\.tasks).filter { $0.kind == .puzzles }.map(\.count) ?? []
        #expect(!sizes.isEmpty && sizes.allSatisfy { $0 == 3 })
    }

    @Test func backgroundStoresQuickResultsAndRebuildsThePlan() async throws {
        let ctx = try context()
        let background = BackgroundAnalysis(engine: FakeEngine(botMoves: []), idleDelay: .zero)
        background.attach(ctx)
        ProfileStore.saveProfile(platform: .chesscom, username: "me", avatarURL: nil, rating: 900, in: ctx)
        let old = TrainingPlan.make(weaknesses: [.allowedMate], rating: 900, ownMistakes: 0)
        ProfileStore.savePlan(old, in: ctx)
        var game = snapshot()
        game.moves = ["e2e4", "e7e5"]
        ProfileStore.saveGames([game], in: ctx)
        UserDefaults.standard.set(true, forKey: Pref.hasOnboarded)
        defer { UserDefaults.standard.removeObject(forKey: Pref.hasOnboarded) }

        background.quick([game])
        background.replanWhenQuickDone()
        try await waitUntil(seconds: 5) { background.pendingQuick == 0 }
        let stored = try #require(try ctx.fetch(FetchDescriptor<GameRecord>()).first?.snapshot)
        #expect(stored.analysis?.pass == .quick)
        #expect(stored.needsFullAnalysis)
        // Rebuilt from the stored games, same start date so the day number stays.
        let plan = try #require(ProfileStore.plan(in: ctx))
        #expect(plan.created == old.created)
        #expect(plan != old)
        // Then the idle full pass replaces the quick one.
        try await waitUntil(seconds: 5) {
            (try? ctx.fetch(FetchDescriptor<GameRecord>()).first?.snapshot?.analysis?.isFull) == true
        }
    }

    @Test func newPlayerPathEstimatesAndPlans() throws {
        let ctx = try context()
        let model = OnboardingModel()
        model.startQuestions()
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

    /// Cancelling an import and then choosing "I'm new to chess" must not keep the abandoned
    /// account's games.
    @Test func cancelledImportThenNewPlayerSavesNoGames() async throws {
        let ctx = try context()
        let background = BackgroundAnalysis(engine: FakeEngine(botMoves: []), idleDelay: .zero)
        let model = OnboardingModel()
        model.makeClient = { FakeClient(platform: $0) }
        model.setFastEngine = { _ in }
        model.background = background
        model.go(.find)
        model.pick(PlatformProfile(platform: .chesscom, username: "hikaru", ratings: ["rapid": 1234]))
        try await waitUntil(seconds: 3) { !model.games.isEmpty }
        model.cancelImport()
        #expect(model.games.isEmpty)
        model.startQuestions()
        model.answer(0, 1)
        model.answer(1, 2)
        model.answer(2, 2)
        model.buildPlan(completedLessons: [])
        model.save(in: ctx)
        defer { UserDefaults.standard.removeObject(forKey: Pref.hasOnboarded) }
        #expect(try ctx.fetchCount(FetchDescriptor<GameRecord>()) == 0)
        #expect(model.plan?.focus.first == .missedMate)  // the new-player answers, not the games
    }

    @Test func coachTextChipsParse() {
        #expect(CoachText.segments("on [c4] and [f7].") == [.words("on "), .square("c4"), .words(" and "), .square("f7"), .words(".")])
        #expect(CoachText.segments("[x9] stays text") == [.words("[x9] stays text")])
        #expect(CoachText.plain("**Hi** [e4]") == "Hi e4")
        #expect(SquareChip.isLight("h1") && !SquareChip.isLight("a1"))
    }

    private func waitUntil(seconds: Double = 3, _ condition: @MainActor () -> Bool) async throws {
        let end = ContinuousClock.now + .seconds(seconds)
        while !condition() && ContinuousClock.now < end { try await Task.sleep(for: .milliseconds(30)) }
        #expect(condition())
    }
}

/// No network: "hikaru" is on chess.com only, "both" on both, "slow" rate-limits on Lichess.
private struct FakeClient: GameImportClient {
    let platform: ImportPlatform

    func profile(_ username: String) async throws -> PlatformProfile {
        switch (username, platform) {
        case ("hikaru", .chesscom), ("both", _):
            return PlatformProfile(platform: platform, username: username, ratings: ["rapid": 1234], gameCount: 120)
        case ("slow", .lichess):
            throw ImportError.rateLimited
        default:
            throw ImportError.userNotFound
        }
    }

    func recentGames(_ username: String, limit: Int, progress: @Sendable (Int) -> Void) async throws -> [ImportedGame] {
        let reviewed = """
        [White "hikaru"]
        [Black "opp"]
        [Result "1-0"]
        [Link "https://www.chess.com/game/live/1"]

        1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7# 1-0
        """
        let plain = """
        [White "opp2"]
        [Black "hikaru"]
        [Result "0-1"]
        [Link "https://www.chess.com/game/live/2"]

        1. d4 d5 2. Nc3 Nf6 3. Bg5 e6 4. h4 Be7 0-1
        """
        progress(2)
        return [ImportedGame(pgn: reviewed, accuracy: PlatformAccuracy(white: 81.5, black: 40, source: "chesscom")),
                ImportedGame(pgn: plain)]
    }
}
