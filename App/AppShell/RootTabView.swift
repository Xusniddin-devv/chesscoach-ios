import SwiftUI
import SwiftData
import ChessCore

struct RootTabView: View {
    enum TabID: Hashable { case home, puzzles, learn, profile }

    @Environment(EngineHub.self) private var hub
    @AppStorage(Pref.hasOnboarded) private var hasOnboarded = false
    @Query private var records: [GameRecord]
    @State private var tab: TabID = .home

    var body: some View {
        Group {
            if hasOnboarded || Self.skipsOnboarding {
                tabs.transition(.opacity)
            } else {
                OnboardingFlow { withAnimation(.easeInOut(duration: 0.4)) { hasOnboarded = true } }
                    .transition(.opacity)
            }
        }
        .tint(DS.Color.accent)
        .preferredColorScheme(.dark)
        // The player's level follows the saved games: Training thresholds and wording.
        .task(id: records.reduce(0) { $0 + $1.snapshotData.count }) {
            let profile = ProfileModel(records: records)
            hub.playerRating = profile.trainingRating
            hub.playerTier = profile.tier
        }
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
            if ["settings", "paywall"].contains(UserDefaults.standard.string(forKey: "debugOpen")) { tab = .profile }
        }
        #endif
    }

    /// Debug screenshot hooks for other screens (autoplay, picker, settings, review, tabs)
    /// skip onboarding.
    private static var skipsOnboarding: Bool {
        #if DEBUG
        let d = UserDefaults.standard
        return ["debugAutoplay", "debugScreen", "debugOpen", "debugTab", "debugReview", "debugFreeplay"]
            .contains { d.string(forKey: $0) != nil }
        #else
        return false
        #endif
    }
}
