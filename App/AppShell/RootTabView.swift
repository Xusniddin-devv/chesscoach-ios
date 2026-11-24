import SwiftUI
import SwiftData
import ChessCore

struct RootTabView: View {
    enum TabID: Hashable { case home, puzzles, learn, profile }

    @Environment(EngineHub.self) private var hub
    @Query private var records: [GameRecord]
    @State private var tab: TabID = .home

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", image: "Icons/tab-home", value: .home) { HomeView() }
            Tab("Puzzles", image: "Icons/tab-puzzle", value: .puzzles) { ComingSoonView(title: "Puzzles") }
            Tab("Learn", image: "Icons/tab-learn", value: .learn) { ComingSoonView(title: "Learn") }
            Tab("Profile", image: "Icons/tab-profile", value: .profile) { ProfileView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(DS.Color.accent)
        .preferredColorScheme(.dark)
        // The player's level follows the saved games: Training thresholds and wording.
        .task(id: records.reduce(0) { $0 + $1.snapshotData.count }) {
            let profile = ProfileModel(records: records)
            hub.playerRating = profile.trainingRating
            hub.playerTier = profile.tier
        }
        #if DEBUG
        .task { if UserDefaults.standard.string(forKey: "debugTab") == "profile" { tab = .profile } }
        #endif
    }
}
