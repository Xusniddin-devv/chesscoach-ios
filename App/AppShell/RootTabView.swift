import SwiftUI

struct RootTabView: View {
    @AppStorage(Pref.hasOnboarded) private var hasOnboarded = false

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
    }

    private var tabs: some View {
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
    }

    /// Debug screenshot hooks for other screens (autoplay, picker, settings) skip onboarding.
    private static var skipsOnboarding: Bool {
        #if DEBUG
        let d = UserDefaults.standard
        return ["debugAutoplay", "debugScreen", "debugOpen"].contains { d.string(forKey: $0) != nil }
        #else
        return false
        #endif
    }
}
