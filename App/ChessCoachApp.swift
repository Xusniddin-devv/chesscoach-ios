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
        .modelContainer(for: GameRecord.self)
    }
}
