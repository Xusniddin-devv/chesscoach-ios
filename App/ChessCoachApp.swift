import SwiftUI
import SwiftData

@main
struct ChessCoachApp: App {
    @State private var hub = EngineHub()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(hub)
                .task {
                    await hub.configure()
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-engineBenchmark") {
                        await EngineBenchmark.runHeadless()
                    }
#endif
                }
        }
        .modelContainer(for: GameRecord.self, inMemory: Self.inMemoryStore)
    }

    /// DEBUG `-debugEmptyStore 1`: an empty in-memory store (first-launch screenshots without
    /// wiping the saved games).
    private static var inMemoryStore: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "debugEmptyStore") != nil
        #else
        false
        #endif
    }
}
