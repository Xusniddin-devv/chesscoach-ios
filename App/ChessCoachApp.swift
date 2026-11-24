import SwiftUI
import SwiftData

@main
struct ChessCoachApp: App {
    @State private var hub = EngineHub()
    // feat/settings-paywall: Pro status + CloudKit-or-local store
    @State private var entitlements = Entitlements()
    @State private var analysis = BackgroundAnalysis()
    private let container = ModelStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(hub)
                .environment(entitlements)
                .environment(analysis)
                .task {
                    await hub.configure()
                    analysis.attach(container.mainContext)
                    if UserDefaults.standard.bool(forKey: Pref.hasOnboarded) { analysis.resumeStoredWork() }
                    await entitlements.start()
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-engineBenchmark") {
                        await EngineBenchmark.runHeadless()
                    }
#endif
                }
        }
        .modelContainer(container)
    }
}
