import Foundation
import SwiftData
import OSLog

/// The SwiftData container. Syncs through the CloudKit private database
/// (`iCloud.uz.xq.chessc`) when the build has `CLOUDKIT_SYNC` (Config/App.xcconfig) and the
/// device is signed in to iCloud; otherwise — no account, Simulator without one, missing
/// entitlement — the same store file stays local. Models must stay CloudKit-compatible
/// (every property defaulted, no unique constraints).
///
/// Every @Model type lives in `models` (DataReset clears the same list).
enum ModelStore {
    static let containerID = "iCloud.uz.xq.chessc"
    static let models: [any PersistentModel.Type] = [
        GameRecord.self, PuzzleProgress.self, LessonProgress.self, StreakState.self,
    ]
    static let schema = Schema(models)

    private static let log = Logger(subsystem: "uz.xq.chessc", category: "persistence")

    /// Whether this launch syncs with iCloud.
    nonisolated(unsafe) private(set) static var isSyncing = false

    static func makeContainer() -> ModelContainer {
        #if CLOUDKIT_SYNC
        let inTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !inTests, FileManager.default.ubiquityIdentityToken != nil {
            do {
                let config = ModelConfiguration(schema: schema, cloudKitDatabase: .private(containerID))
                let container = try ModelContainer(for: schema, configurations: config)
                isSyncing = true
                return container
            } catch {
                log.error("CloudKit store unavailable, using the local store: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
        do {
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            // Last resort: keep the app usable this session rather than crash.
            log.fault("Local store failed, using memory: \(error.localizedDescription, privacy: .public)")
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: memory)
        }
    }
}
