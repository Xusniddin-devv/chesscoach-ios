import SwiftUI
import SwiftData
import ChessCore
import CoreData

struct RootTabView: View {
    enum TabID: Hashable { case home, puzzles, learn, profile }

    @Environment(EngineHub.self) private var hub
    @Environment(\.modelContext) private var context
    @AppStorage(Pref.hasOnboarded) private var hasOnboarded = false
    @Query private var records: [GameRecord]
    /// Onboarding saves the profile as it finishes, so a profile row means "onboarded" on
    /// some device: one that arrives through iCloud (new phone, reinstall) skips onboarding.
    @Query private var profiles: [UserProfile]
    @State private var tab: TabID = .home
    @State private var saveIssues = SaveIssues.shared

    private var isOnboarded: Bool { hasOnboarded || !profiles.isEmpty }

    var body: some View {
        Group {
            if isOnboarded || Self.skipsOnboarding {
                tabs.transition(.opacity)
            } else {
                OnboardingFlow { withAnimation(.easeInOut(duration: 0.4)) { hasOnboarded = true } }
                    .transition(.opacity)
            }
        }
        .tint(DS.Color.accent)
        .preferredColorScheme(.dark)
        // The player's level follows the saved games: Training thresholds and wording.
        .task(id: GameRecord.fingerprint(records)) {
            let profile = ProfileModel(records: records)
            hub.playerRating = profile.trainingRating
            hub.playerTier = profile.tier
        }
        // A profile synced from another device: onboarded here too (the background full
        // pass waits for this flag).
        .onChange(of: profiles.isEmpty, initial: true) { _, empty in
            if !empty && !hasOnboarded { hasOnboarded = true }
        }
        // Copies of one game left by sync (a re-import on a second phone) are merged at
        // launch and whenever iCloud delivers changes.
        .task { GameRecord.mergeDuplicates(in: context) }
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
