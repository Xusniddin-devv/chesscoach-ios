import SwiftUI
import SwiftData

@main
struct ChessCoachApp: App {
    @State private var hub = EngineHub()
    // Pro status + CloudKit-or-local store
    @State private var entitlements = Entitlements()
    private let container = ModelStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(hub)
                .environment(entitlements)
                .task {
                    await hub.configure()
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
