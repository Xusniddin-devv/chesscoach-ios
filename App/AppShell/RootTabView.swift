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
            Tab("Home", systemImage: "house", value: .home) { HomeView() }
            Tab("Puzzles", systemImage: "puzzlepiece", value: .puzzles) { ComingSoonView(title: "Puzzles") }
            Tab("Learn", systemImage: "book", value: .learn) { ComingSoonView(title: "Learn") }
            Tab("Profile", systemImage: "person", value: .profile) { ProfileView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(DS.Color.accent)
        .preferredColorScheme(.dark)
        // The player's level follows the saved games: Training thresholds and wording.
        .task(id: records.reduce(0) { $0 + $1.snapshotData.count }) {
            hub.playerRating = ProfileModel(records: records).trainingRating
        }
        #if DEBUG
        .task { if UserDefaults.standard.string(forKey: "debugTab") == "profile" { tab = .profile } }
        #endif
    }
}
