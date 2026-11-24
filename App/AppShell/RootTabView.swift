import SwiftUI
import SwiftData
import ChessCore
import CoreData

struct RootTabView: View {
    enum TabID: Hashable { case home, puzzles, learn, profile }

    @Environment(EngineHub.self) private var hub
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.hardPaywall) private var hardPaywall
    @Environment(GameAutoSync.self) private var autoSync: GameAutoSync?
    @Environment(BackgroundAnalysis.self) private var analysis: BackgroundAnalysis?
    @AppStorage(Pref.hasOnboarded) private var hasOnboarded = false
    @Query private var records: [GameRecord]
    /// Onboarding saves the profile as it finishes, so a profile row means "onboarded" on
    /// some device: one that arrives through iCloud (new phone, reinstall) skips onboarding.
    @Query private var profiles: [UserProfile]
    @State private var tab: TabID = .home
    @State private var saveIssues = SaveIssues.shared
    /// Set while the onboarding flow is on screen: it saves the profile before its own
    /// paywall step, and that must not swap it for the launch gate.
    @State private var onboardingInProgress = false
    /// The user is mid-onboarding (picked an account or started the questions).
    @State private var onboardingEngaged = false
    @State private var launched = false

    private static var inTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    private var isOnboarded: Bool {
        Self.showsTabs(hasOnboarded: hasOnboarded, hasProfile: !profiles.isEmpty, onboardingEngaged: onboardingEngaged)
    }

    /// Onboarded here, or a profile synced from another device (new phone, reinstall) before
    /// the user started onboarding. Once they have picked an account, a synced profile must
    /// not cut the flow: their choice would never be saved and the old account's rating and
    /// goal would show instead. Onboarding's save then replaces that profile.
    static func showsTabs(hasOnboarded: Bool, hasProfile: Bool, onboardingEngaged: Bool) -> Bool {
        hasOnboarded || (hasProfile && !onboardingEngaged)
    }

    private var route: LaunchRoute {
        if Self.skipsOnboarding { return .tabs }
        return LaunchRoute.resolve(onboarded: isOnboarded, onboardingInProgress: onboardingInProgress,
                                   hardPaywall: hardPaywall, status: entitlements.status)
    }

    var body: some View {
        Group {
            switch route {
            case .tabs:
                tabs.transition(.opacity)
            case .onboarding:
                OnboardingFlow(onEngagedChange: { onboardingEngaged = $0 }) {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        hasOnboarded = true
                        onboardingInProgress = false
                    }
                }
                .onAppear { onboardingInProgress = true }
                .transition(.opacity)
            case .checking:
                DS.Color.background.ignoresSafeArea()
            case .paywall:
                PaywallGate().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: route)
        .tint(DS.Color.accent)
        .preferredColorScheme(.dark)
        // The player's level: the platform rating for an imported player, else the saved
        // games' estimate. Training thresholds and wording.
        .task(id: [GameRecord.fingerprint(records), profiles.current?.platformRating ?? 0]) {
            let profile = ProfileModel(records: records, platformRating: profiles.current?.platformRating)
            hub.playerRating = profile.trainingRating
            hub.playerTier = profile.tier
        }
        // A profile synced from another device: onboarded here too (the background full
        // pass waits for this flag).
        .onChange(of: profiles.isEmpty, initial: true) { _, empty in
            if !empty && !hasOnboarded && !onboardingEngaged { hasOnboarded = true }
        }
        // Copies of one game left by sync (a re-import on a second phone) are merged at
        // launch and whenever iCloud delivers changes.
        .task { GameRecord.mergeDuplicates(in: context) }
        // Auto-sync of the linked account on launch and every return to the foreground
        // (throttled inside); Pro is remembered for background refreshes.
        .onChange(of: entitlements.isPro, initial: true) { old, pro in
            // The store answers after launch: a launch-time `false` is not a lapse.
            guard pro || old != pro else { return }
            autoSync?.notePro(pro)
            if pro { syncNow(.launch) }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            syncNow(launched ? .foreground : .launch)
            launched = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in
            GameRecord.mergeDuplicates(in: context)
        }
        .overlay(alignment: .top) { SaveNotice(issues: saveIssues).animation(.snappy, value: saveIssues.failed) }
        #if DEBUG
        // `-debugSaveNotice 1`: the failed-save notice (screenshots).
        .task {
            guard UserDefaults.standard.string(forKey: "debugSaveNotice") != nil else { return }
            saveIssues.report("your puzzle progress", error: CocoaError(.fileWriteUnknown), context: context)
        }
        #endif
    }

    private func syncNow(_ trigger: GameAutoSync.Trigger) {
        guard isOnboarded, !Self.inTests, let autoSync else { return }
        Task { await autoSync.sync(in: context, analysis: analysis, isPro: entitlements.isPro, trigger: trigger) }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab("Home", image: "Icons/tab-home", value: .home) { HomeView() }
            Tab("Puzzles", image: "Icons/tab-puzzle", value: .puzzles) { PuzzlesView() }
            Tab("Learn", image: "Icons/tab-learn", value: .learn) { LearnView() }
            Tab("Profile", image: "Icons/tab-profile", value: .profile) { ProfileView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        #if DEBUG
        .task {
            switch UserDefaults.standard.string(forKey: "debugTab") {
            case "profile": tab = .profile
            case "puzzles": tab = .puzzles
            case "learn": tab = .learn
            default: break
            }
            if ["settings", "paywall", "licenses"].contains(UserDefaults.standard.string(forKey: "debugOpen")) { tab = .profile }
        }
        #endif
    }

    /// Debug screenshot hooks for other screens (autoplay, picker, settings, review, tabs)
    /// skip onboarding.
    private static var skipsOnboarding: Bool {
        #if DEBUG
        let d = UserDefaults.standard
        return ["debugAutoplay", "debugScreen", "debugOpen", "debugTab", "debugReview", "debugFreeplay", "debugEditor"]
            .contains { d.string(forKey: $0) != nil }
        #else
        return false
        #endif
    }
}
