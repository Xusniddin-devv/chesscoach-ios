import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") { HomeView() }
            Tab("Puzzles", systemImage: "puzzlepiece") { PuzzlesView() }
            Tab("Learn", systemImage: "book") { LearnView() }
            Tab("Profile", systemImage: "person") {
#if DEBUG
                DebugProfilePlaceholder()  // long-press on a system tab item is not available
#else
                ComingSoonView(title: "Profile")
#endif
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(DS.Color.accent)
        .preferredColorScheme(.dark)
    }
}
