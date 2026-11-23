import SwiftUI
import SwiftData

@main
struct ChessCoachApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var hub = EngineHub()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(hub)
        }
        .modelContainer(for: GameRecord.self)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await hub.recoverIfNeeded() } }
        }
    }
}
