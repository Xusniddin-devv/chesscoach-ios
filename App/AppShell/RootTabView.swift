import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") { HomeView() }
            Tab("Puzzles", systemImage: "puzzlepiece") { ComingSoonView(title: "Puzzles") }
            Tab("Learn", systemImage: "book") { ComingSoonView(title: "Learn") }
            Tab("Profile", systemImage: "person") { ComingSoonView(title: "Profile") }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(DS.Color.accent)
        .preferredColorScheme(.dark)
    }
}
