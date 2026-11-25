import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct ChessCoachApp: App {
    @State private var hub = EngineHub()
    // Pro status + CloudKit-or-local store
    @State private var entitlements = Entitlements()
    @State private var analysis = BackgroundAnalysis()
    @State private var autoSync = GameAutoSync()
    @Environment(\.scenePhase) private var scenePhase
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
                .environment(autoSync)
                // Pro status on its own task: the launch gate stays blank until it answers, so it
                // must not wait for the engine to load its nets (seconds on a cold start).
                .task { await entitlements.start() }
                .task {
                    // Bot strength: last downloaded numbers now, a fresh copy in the background.
                    BotTuningSync.applyCached()
                    if !Self.isTestHost { await BotTuningSync.refresh() }
                }
                .task {
                    await hub.configure()
                    analysis.attach(container.mainContext)
                    if UserDefaults.standard.bool(forKey: Pref.hasOnboarded) { analysis.resumeStoredWork() }
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-engineBenchmark") {
                        await EngineBenchmark.runHeadless()
                    }
#endif
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Self.scheduleBackgroundSync() }
        }
        // Auto-sync while the app is in the background: games are saved now and analysed on
        // the next launch (`resumeStoredWork`). iOS decides when this runs.
        .backgroundTask(.appRefresh(GameAutoSync.backgroundTaskID)) {
            Self.scheduleBackgroundSync()
            await syncInBackground()
        }
    }

    @MainActor
    private func syncInBackground() async {
        guard UserDefaults.standard.bool(forKey: Pref.hasOnboarded) else { return }
        await autoSync.sync(in: container.mainContext, analysis: nil, isPro: entitlements.isPro, trigger: .background)
    }

    /// Asks iOS for the next background refresh (fails quietly where unsupported, like the Simulator).
    nonisolated static func scheduleBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: GameAutoSync.backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: GameAutoSync.backgroundInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
