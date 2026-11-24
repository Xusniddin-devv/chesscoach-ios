import Testing
import SwiftData
import Foundation
import ChessCore
@testable import ChessCoach

/// The owner's report: onboarding with chess.com "hikaru" revealed 2838 (rapid), but Home and
/// Profile showed the app's own estimate. An imported player's rating is the platform's.
@MainActor
struct ImportedRatingTests {
    private let ctx: ModelContext

    init() throws {
        let container = try ModelContainer(
            for: ModelStore.schema,
            configurations: ModelConfiguration(schema: ModelStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        ctx = ModelContext(container)
    }

    private func imported(_ i: Int, result: GameResult, accuracy: Double) -> GameSnapshot {
        var s = GameSnapshot(
            id: UUID(), date: Date(timeIntervalSinceNow: -Double(i + 10) * 3_600), botId: "chesscom",
            userColor: .white, mode: .silent, startFen: Rules.startFen, moves: ["e2e4"], sans: ["e4"],
            result: result, verdicts: [], analysisVersion: 1, playerRatingUsed: 3450, source: "chesscom",
            opponentName: "WiktorGolis", opponentRating: 3050)
        s.platformAccuracy = PlatformAccuracy(white: accuracy, black: 80, source: "chesscom")
        return s
    }

    private func botGame(_ bot: String, result: GameResult, minutesAgo: Double) throws {
        let s = GameSnapshot(
            id: UUID(), date: Date(timeIntervalSinceNow: -minutesAgo * 60), botId: bot, userColor: .white,
            mode: .training, startFen: Rules.startFen, moves: [], sans: [], result: result, verdicts: [],
            analysisVersion: 1, playerRatingUsed: 800)
        ctx.insert(try GameRecord(snapshot: s))
    }

    /// Onboarding's save for hikaru (rapid 2838, goal 2900), then a win over Pip and a loss to Apex.
    private func onboardHikaru() throws -> UserProfile {
        ProfileStore.saveProfile(platform: .chesscom, username: "Hikaru", avatarURL: nil, rating: 2838, in: ctx)
        ProfileStore.saveGoal(rating: 2900, months: 3, in: ctx)
        let games = (0..<20).map { imported($0, result: $0 == 7 ? .blackWins : .whiteWins, accuracy: 86) }
        ProfileStore.saveGames(games, in: ctx)
        try botGame("pip", result: .whiteWins, minutesAgo: 20)
        try botGame("apex", result: .blackWins, minutesAgo: 5)
        try ctx.save()
        return try #require(ProfileStore.profile(in: ctx))
    }

    private var records: [GameRecord] { (try? ctx.fetch(FetchDescriptor<GameRecord>())) ?? [] }

    @Test func homeAndProfileShowThePlatformRating() throws {
        let profile = try onboardHikaru()
        #expect(profile.platformRating == 2838)
        let model = ProfileModel(records: records, platformRating: profile.platformRating)
        // What Home and Profile showed before: the app's estimate, clamped at 2400.
        #expect(model.estimate == 2400)
        #expect(model.rating == 2838)
        #expect(model.trainingRating == 2838)
        #expect(model.tier == .king)
        // The goal stays ahead of the rating Home and Profile show.
        #expect(try #require(profile.goalRating) > model.rating!)
    }

    @Test func strongImportIsNotSentToPip() throws {
        let profile = try onboardHikaru()
        let model = ProfileModel(records: records, platformRating: profile.platformRating)
        let ladder = BotLadder(records: records, profile: model)
        #expect(ladder.next?.id == "apex")
        #expect(Bot.all.allSatisfy(ladder.isOpen))
    }

    @Test func newPlayerKeepsTheAppEstimate() throws {
        ProfileStore.saveProfile(platform: nil, username: "", avatarURL: nil, rating: 800, in: ctx)
        try botGame("ron", result: .whiteWins, minutesAgo: 3)
        try botGame("ron", result: .whiteWins, minutesAgo: 2)
        try botGame("ron", result: .blackWins, minutesAgo: 1)
        try ctx.save()
        let profile = try #require(ProfileStore.profile(in: ctx))
        #expect(profile.platformRating == nil)
        let model = ProfileModel(records: records, platformRating: profile.platformRating)
        #expect(model.rating == model.estimate)
        #expect(model.rating == 860)  // (980 + 980 + 620) / 3
    }

    // MARK: A synced profile arriving mid-onboarding

    /// The "960 → 1500" in the report: on a reinstall iCloud delivers the previous account's
    /// profile while the user is importing hikaru; the gate swapped onboarding for the tabs
    /// at once, hikaru was never saved, and Home showed the old account's rating and goal.
    @Test func syncedProfileDoesNotCutAnOnboardingInProgress() {
        // Before the user starts (welcome, find): a synced profile means "onboarded elsewhere".
        #expect(OnboardingModel.Step.welcome.isEngaged == false)
        #expect(OnboardingModel.Step.find.isEngaged == false)
        #expect(RootTabView.showsTabs(hasOnboarded: false, hasProfile: true, onboardingEngaged: false))
        // Once an account is picked (or the questions started), onboarding runs to its save.
        for step: OnboardingModel.Step in [.importing, .question(0), .reveal, .goal, .plan] {
            #expect(step.isEngaged)
        }
        #expect(!RootTabView.showsTabs(hasOnboarded: false, hasProfile: true, onboardingEngaged: true))
        #expect(RootTabView.showsTabs(hasOnboarded: true, hasProfile: true, onboardingEngaged: true))
        #expect(!RootTabView.showsTabs(hasOnboarded: false, hasProfile: false, onboardingEngaged: false))
    }

    @Test func savingOnboardingReplacesASyncedProfile() throws {
        // The old account's row arrived through sync; hikaru's save takes it over.
        ctx.insert(UserProfile(platform: "chesscom", username: "invaluable_me", currentRating: 844))
        try ctx.save()
        let profile = try onboardHikaru()
        #expect(try ctx.fetchCount(FetchDescriptor<UserProfile>()) == 1)
        #expect(profile.username == "Hikaru" && profile.platformRating == 2838 && profile.goalRating == 2900)
    }

    // MARK: Daily refresh from the platform

    @Test func refreshUpdatesThePlatformRatingAtMostOnceADay() async throws {
        let profile = try onboardHikaru()
        let defaults = try #require(UserDefaults(suiteName: "ImportedRatingTests.refresh"))
        defaults.removePersistentDomain(forName: "ImportedRatingTests.refresh")
        let calls = Calls()
        let client: (ImportPlatform) -> any GameImportClient = { RatingClient(platform: $0, rapid: 2851, calls: calls) }
        let now = Date()

        await PlatformRatingRefresh.refreshIfDue(in: ctx, now: now, defaults: defaults, client: client)
        #expect(profile.currentRating == 2851)
        #expect(calls.count == 1)

        // Within a day: no request.
        await PlatformRatingRefresh.refreshIfDue(in: ctx, now: now.addingTimeInterval(3_600), defaults: defaults, client: client)
        #expect(calls.count == 1)
        // A day later: asked again.
        await PlatformRatingRefresh.refreshIfDue(in: ctx, now: now.addingTimeInterval(90_000), defaults: defaults, client: client)
        #expect(calls.count == 2)
    }

    @Test func refreshFailsSilentlyAndSkipsNewPlayers() async throws {
        let profile = try onboardHikaru()
        let defaults = try #require(UserDefaults(suiteName: "ImportedRatingTests.fail"))
        defaults.removePersistentDomain(forName: "ImportedRatingTests.fail")
        let calls = Calls()
        await PlatformRatingRefresh.refreshIfDue(in: ctx, defaults: defaults) { RatingClient(platform: $0, rapid: nil, calls: calls) }
        #expect(profile.currentRating == 2838)

        ProfileStore.saveProfile(platform: nil, username: "", avatarURL: nil, rating: 600, in: ctx)
        defaults.removePersistentDomain(forName: "ImportedRatingTests.fail")
        await PlatformRatingRefresh.refreshIfDue(in: ctx, defaults: defaults) { RatingClient(platform: $0, rapid: 2000, calls: calls) }
        #expect(calls.count == 1)
        #expect(ProfileStore.profile(in: ctx)?.currentRating == 600)
    }
}

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var count: Int { lock.withLock { n } }
    func hit() { lock.withLock { n += 1 } }
}

/// The platform profile with one rapid rating; nil = the request fails.
private struct RatingClient: GameImportClient {
    let platform: ImportPlatform
    let rapid: Int?
    let calls: Calls

    func profile(_ username: String) async throws -> PlatformProfile {
        calls.hit()
        guard let rapid else { throw ImportError.network }
        return PlatformProfile(platform: platform, username: username, ratings: ["rapid": rapid, "blitz": 3442])
    }

    func recentGames(_ username: String, limit: Int, progress: @Sendable (Int) -> Void) async throws -> [ImportedGame] { [] }
}
