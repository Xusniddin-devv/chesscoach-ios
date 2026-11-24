import Testing
import SwiftData
import Foundation
import ChessCore
@testable import ChessCoach

/// Auto-sync of the linked account with a fake platform: only new games are saved, the rating
/// is refreshed, it is Pro / toggle / link gated, throttled, and backs off on failures.
@MainActor
struct GameAutoSyncTests {
    private let ctx: ModelContext
    private let defaults: UserDefaults
    private let sync: GameAutoSync
    private let client = FakePlatform()
    private var clock = Date(timeIntervalSince1970: 1_900_000_000)

    init() throws {
        let container = try ModelContainer(
            for: ModelStore.schema,
            configurations: ModelConfiguration(schema: ModelStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        ctx = ModelContext(container)
        let suite = "GameAutoSyncTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        sync = GameAutoSync(defaults: defaults)
        let client = client
        sync.makeClient = { _ in client }
        let now = clock
        sync.now = { now }
    }

    /// hikaru linked at onboarding with two games stored.
    private func linkHikaru() throws {
        ProfileStore.saveProfile(platform: .chesscom, username: "Hikaru", avatarURL: nil, rating: 2838, in: ctx)
        let stored = try [FakePlatform.game(1, hoursAgo: 30), FakePlatform.game(0, hoursAgo: 40)].map {
            try PGNImporter.snapshot(game: $0, username: "Hikaru", platform: .chesscom)
        }
        ProfileStore.saveGames(stored, in: ctx)
    }

    private var importedCount: Int {
        ((try? ctx.fetch(FetchDescriptor<GameRecord>())) ?? []).compactMap(\.snapshot).filter(\.isImported).count
    }

    @Test func savesOnlyNewGamesAndRefreshesTheRating() async throws {
        try linkHikaru()
        client.set(games: [FakePlatform.game(3, hoursAgo: 1), FakePlatform.game(2, hoursAgo: 2),
                           FakePlatform.game(1, hoursAgo: 30), FakePlatform.game(0, hoursAgo: 40)], rapid: 2851)
        let added = await sync.sync(in: ctx, analysis: nil, isPro: true, trigger: .launch)
        #expect(added == 2)
        #expect(importedCount == 4)
        #expect(ProfileStore.profile(in: ctx)?.currentRating == 2851)
        #expect(ProfileModel(records: try ctx.fetch(FetchDescriptor<GameRecord>()),
                             platformRating: ProfileStore.profile(in: ctx)?.platformRating).rating == 2851)

        // Back to the foreground a minute later: throttled, no request.
        let calls = client.calls
        #expect(await sync.sync(in: ctx, analysis: nil, isPro: true, trigger: .foreground) == nil)
        #expect(client.calls == calls)
        // Pull to refresh: runs, nothing new, nothing duplicated.
        #expect(await sync.sync(in: ctx, analysis: nil, isPro: true, trigger: .pull) == 0)
        #expect(importedCount == 4)
    }

    @Test func gatedByProToggleAndLink() async throws {
        try linkHikaru()
        client.set(games: [FakePlatform.game(5, hoursAgo: 1)], rapid: 2838)
        #expect(await sync.sync(in: ctx, analysis: nil, isPro: false, trigger: .pull) == nil)
        #expect(client.calls == 0)

        defaults.set(false, forKey: Pref.autoSync)
        #expect(await sync.sync(in: ctx, analysis: nil, isPro: true, trigger: .pull) == nil)
        defaults.removeObject(forKey: Pref.autoSync)

        // Pro seen in the foreground: a background launch syncs before the store answers.
        sync.notePro(true)
        #expect(await sync.sync(in: ctx, analysis: nil, isPro: false, trigger: .background) == 1)

        // Unlinked: no syncs, the rating stays the platform's.
        GameAutoSync.unlink(in: ctx, defaults: defaults)
        #expect(GameAutoSync.linkedAccount(in: ctx) == nil)
        #expect(ProfileStore.profile(in: ctx)?.platformRating == 2838)
        #expect(await sync.sync(in: ctx, analysis: nil, isPro: true, trigger: .pull) == nil)
    }

    @Test func newPlayersHaveNothingToSync() async {
        ProfileStore.saveProfile(platform: nil, username: "", avatarURL: nil, rating: 600, in: ctx)
        #expect(await sync.sync(in: ctx, analysis: nil, isPro: true, trigger: .pull) == nil)
        #expect(client.calls == 0)
    }

    @Test func rateLimitBacksOffEvenAPull() async throws {
        try linkHikaru()
        client.fail(with: .rateLimited)
        #expect(await sync.sync(in: ctx, analysis: nil, isPro: true, trigger: .launch) == nil)
        #expect(sync.schedule.failures == 1)
        #expect(sync.schedule.retryAfter == clock.addingTimeInterval(SyncSchedule.throttle))
        let calls = client.calls
        #expect(await sync.sync(in: ctx, analysis: nil, isPro: true, trigger: .pull) == nil)
        #expect(client.calls == calls)
        #expect(importedCount == 2)
    }

    @Test func newGamesGoToTheBackgroundAnalysis() async throws {
        try linkHikaru()
        let background = BackgroundAnalysis(engine: FakeEngine(botMoves: []), idleDelay: .zero)
        background.attach(ctx)
        client.set(games: [FakePlatform.game(7, hoursAgo: 1)], rapid: 2838)
        #expect(await sync.sync(in: ctx, analysis: background, isPro: true, trigger: .pull) == 1)
        let id = try #require(PGNImporter.stableId(platform: .chesscom, pgn: FakePlatform.game(7, hoursAgo: 1).pgn))
        let end = ContinuousClock.now + .seconds(5)
        func analysed() -> Bool {
            (try? ctx.fetch(FetchDescriptor<GameRecord>(predicate: #Predicate { $0.id == id })).first?.snapshot?.analysis) != nil
        }
        while !analysed() && ContinuousClock.now < end { try await Task.sleep(for: .milliseconds(30)) }
        #expect(analysed())
    }

    @Test func unanalysedImportHasNoPuzzleLine() throws {
        let snapshot = try PGNImporter.snapshot(game: FakePlatform.game(9, hoursAgo: 1), username: "Hikaru", platform: .chesscom)
        let record = try GameRecord(snapshot: snapshot)
        #expect(HomeView.importedPuzzlesLine(ProfileModel.Game(record: record, snapshot: snapshot, accuracy: nil)) == nil)
    }
}

/// A chess.com account: `games` newest first, one rapid rating; or every request failing.
private final class FakePlatform: GameImportClient, @unchecked Sendable {
    let platform = ImportPlatform.chesscom
    private let lock = NSLock()
    private var games: [ImportedGame] = []
    private var rapid = 2838
    private var error: ImportError?
    private var _calls = 0

    var calls: Int { lock.withLock { _calls } }

    func set(games: [ImportedGame], rapid: Int) {
        lock.withLock { self.games = games; self.rapid = rapid; error = nil }
    }

    func fail(with error: ImportError) { lock.withLock { self.error = error } }

    func profile(_ username: String) async throws -> PlatformProfile {
        let (rapid, error) = lock.withLock { _calls += 1; return (self.rapid, self.error) }
        if let error { throw error }
        return PlatformProfile(platform: .chesscom, username: username, ratings: ["rapid": rapid])
    }

    func recentGames(_ username: String, limit: Int, progress: @Sendable (Int) -> Void) async throws -> [ImportedGame] {
        let (games, error) = lock.withLock { _calls += 1; return (self.games, self.error) }
        if let error { throw error }
        return Array(games.prefix(limit))
    }

    /// Game `n`, hikaru with White, `hoursAgo` before the tests' clock.
    static func game(_ n: Int, hoursAgo: Double) -> ImportedGame {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        let date = Date(timeIntervalSince1970: 1_900_000_000 - hoursAgo * 3_600)
        formatter.dateFormat = "yyyy.MM.dd"
        let day = formatter.string(from: date)
        formatter.dateFormat = "HH:mm:ss"
        let time = formatter.string(from: date)
        return ImportedGame(pgn: """
        [White "Hikaru"]
        [Black "opp\(n)"]
        [WhiteElo "3400"]
        [BlackElo "3000"]
        [Result "1-0"]
        [UTCDate "\(day)"]
        [UTCTime "\(time)"]
        [Link "https://www.chess.com/game/live/\(1000 + n)"]

        1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7# 1-0
        """)
    }
}
