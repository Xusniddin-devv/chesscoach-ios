import SwiftUI
import SwiftData

@main
struct ChessCoachApp: App {
    @State private var hub = EngineHub()
    // Pro status + CloudKit-or-local store
    @State private var entitlements = Entitlements()
    @State private var analysis = BackgroundAnalysis()
    private let container = ModelStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            Group {
                // As the unit tests' host the app shows nothing: tests host their own roots on
                // in-memory containers, and a second live root's @Query (the launch gate, the
                // onboarding) would observe their saves.
                if Self.isTestHost { Color.clear } else { RootTabView() }
            }
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

    private static let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
