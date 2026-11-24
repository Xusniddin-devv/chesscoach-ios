import SwiftUI
import SwiftData
import Observation
import OSLog
import ChessCore

/// Auto-sync of the linked chess.com / Lichess account (Pro): new games since the newest one
/// stored (`GameSync`), saved like onboarding's import (deduplicated by platform game id) and
/// handed to the background analysis (quick pass first, full later, yielding to the
/// foreground); the platform rating is refreshed on the way.
///
/// Triggers: launch and foreground (at most every 15 min), pull to refresh on Home and Profile
/// (any time), and the background app refresh task. Never blocks the UI; failures are silent
/// and back off (`SyncSchedule`). Only the public username is sent.
@MainActor
@Observable
final class GameAutoSync {
    enum Trigger: Equatable { case launch, foreground, pull, background }

    /// The background app refresh task (also in Info.plist `BGTaskSchedulerPermittedIdentifiers`).
    nonisolated static let backgroundTaskID = "uz.xq.chessc.sync"
    /// How soon iOS may run the next background refresh (it decides the real time).
    nonisolated static let backgroundInterval: TimeInterval = 3 * 3_600

    nonisolated static let scheduleKey = "sync.schedule"
    /// Pro was seen in the foreground: a background launch runs before the store answers.
    nonisolated static let proSeenKey = "sync.proSeen"

    private(set) var isSyncing = false

    private static let log = Logger(subsystem: "uz.xq.chessc", category: "sync")

    @ObservationIgnored var makeClient: (ImportPlatform) -> any GameImportClient = GameAutoSync.client
    @ObservationIgnored var defaults: UserDefaults
    @ObservationIgnored var now: () -> Date = { .now }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The linked account, when there is one: an imported player's platform and username.
    static func linkedAccount(in context: ModelContext) -> (platform: ImportPlatform, username: String)? {
        guard let profile = ProfileStore.profile(in: context), let platform = profile.importPlatform,
              !profile.username.isEmpty else { return nil }
        return (platform, profile.username)
    }

    /// Whether auto-sync applies: Pro, the Settings toggle on (default), an account linked.
    func isEnabled(in context: ModelContext, isPro: Bool) -> Bool {
        (isPro || defaults.bool(forKey: Self.proSeenKey)) && Pref.bool(Pref.autoSync, in: defaults)
            && Self.linkedAccount(in: context) != nil
    }

    /// Remembers Pro for background launches (set from the foreground).
    func notePro(_ isPro: Bool) {
        defaults.set(isPro, forKey: Self.proSeenKey)
    }

    var schedule: SyncSchedule {
        get { defaults.data(forKey: Self.scheduleKey).flatMap { try? JSONDecoder().decode(SyncSchedule.self, from: $0) } ?? SyncSchedule() }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.scheduleKey) }
    }

    /// Runs a sync when due. Returns the new games saved, nil when skipped or failed.
    @discardableResult
    func sync(in context: ModelContext, analysis: BackgroundAnalysis?, isPro: Bool, trigger: Trigger) async -> Int? {
        guard !isSyncing, isEnabled(in: context, isPro: isPro),
              let account = Self.linkedAccount(in: context) else { return nil }
        let started = now()
        var schedule = schedule
        guard schedule.isDue(now: started, force: trigger == .pull) else { return nil }
        schedule.started(at: started)
        self.schedule = schedule
        isSyncing = true
        defer { isSyncing = false }

        let client = makeClient(account.platform)
        do {
            let games = try await GameSync.newGames(client: client, username: account.username,
                                                    stored: Self.importedSnapshots(in: context))
            let rating = (try? await client.profile(account.username))?.currentRating
            // The account may have been changed or unlinked while this ran.
            guard let linked = Self.linkedAccount(in: context), linked == account else { return nil }
            if !games.isEmpty { ProfileStore.saveGames(games, in: context) }
            if let rating, let profile = ProfileStore.profile(in: context), profile.currentRating != rating {
                profile.currentRating = rating
                profile.updated = now()
                context.saveReporting("your rating")
            }
            if !games.isEmpty, trigger != .background {
                analysis?.quick(games)
                analysis?.replanWhenQuickDone()
            }
            schedule.succeeded(at: now())
            self.schedule = schedule
            Self.log.info("Synced \(games.count) new \(account.platform.rawValue, privacy: .public) games (\(String(describing: trigger), privacy: .public))")
            return games.count
        } catch {
            schedule.failed(at: now(), error: error)
            self.schedule = schedule
            Self.log.info("Sync failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Unlinks the account: no more syncs. The platform stays (the rating keeps being the
    /// platform's, frozen at its last value) and so do the imported games.
    static func unlink(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard let profile = ProfileStore.profile(in: context) else { return }
        profile.username = ""
        profile.avatarURL = nil
        profile.updated = .now
        context.saveReporting("your profile")
        defaults.removeObject(forKey: scheduleKey)
    }

    private static func importedSnapshots(in context: ModelContext) -> [GameSnapshot] {
        let records = (try? context.fetch(FetchDescriptor<GameRecord>())) ?? []
        return GameRecord.unique(records).compactMap(\.snapshot).filter(\.isImported)
    }

    nonisolated static func client(_ platform: ImportPlatform) -> any GameImportClient {
        switch platform {
        case .chesscom: ChessComClient()
        case .lichess: LichessClient()
        }
    }
}

/// Pull to refresh runs an auto-sync (Home, Profile); nothing to pull without one.
private struct AutoSyncRefresh: ViewModifier {
    @Environment(GameAutoSync.self) private var autoSync: GameAutoSync?
    @Environment(BackgroundAnalysis.self) private var analysis: BackgroundAnalysis?
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    func body(content: Content) -> some View {
        // `profiles` keeps this current when the account is linked or unlinked.
        if let autoSync, !profiles.isEmpty, autoSync.isEnabled(in: context, isPro: entitlements.isPro) {
            content.refreshable {
                await autoSync.sync(in: context, analysis: analysis, isPro: entitlements.isPro, trigger: .pull)
            }
        } else {
            content
        }
    }
}

extension View {
    func autoSyncRefreshable() -> some View { modifier(AutoSyncRefresh()) }
}
