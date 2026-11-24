import Foundation
import SwiftData
import OSLog

/// The SwiftData container. With `CLOUDKIT_SYNC` (Config/App.xcconfig) the store always
/// opens with CloudKit mirroring to the private database (`iCloud.uz.xq.chessc`): it works
/// without an iCloud account and starts syncing once one exists. It is never toggled on the
/// account state, because a mirrored store reopened without mirroring can open read-only or
/// be purged. The CloudKit and local configurations use separate files (`cloud.store`,
/// `local.store`), so the fallback never opens the mirrored file. Models must stay
/// CloudKit-compatible (every property defaulted, no unique constraints).
///
/// Every @Model type lives in `models` (DataReset clears the same list).
enum ModelStore {
    static let containerID = "iCloud.uz.xq.chessc"
    static let models: [any PersistentModel.Type] = [
        GameRecord.self, PuzzleProgress.self, LessonProgress.self, StreakState.self,
        UserProfile.self, TrainingPlanRecord.self,
    ]
    static let schema = Schema(models)

    private static let log = Logger(subsystem: "uz.xq.chessc", category: "persistence")

    /// Whether this launch opened the CloudKit-mirrored store.
    nonisolated(unsafe) private(set) static var isSyncing = false

    enum Mode: String { case cloud, local }

    /// The store file of a mode, in `directory` (Application Support).
    static func storeURL(_ mode: Mode, in directory: URL = .applicationSupportDirectory) -> URL {
        directory.appending(path: "\(mode.rawValue).store")
    }

    /// Builds before separate files kept everything in SwiftData's `default.store`. Moves it
    /// (with its -wal / -shm files) to `target` once, when `target` doesn't exist yet.
    /// Returns whether it moved.
    @discardableResult
    static func migrateLegacyStore(to target: URL, in directory: URL = .applicationSupportDirectory) -> Bool {
        let fm = FileManager.default
        let legacy = directory.appending(path: "default.store")
        guard fm.fileExists(atPath: legacy.path(percentEncoded: false)),
              !fm.fileExists(atPath: target.path(percentEncoded: false)) else { return false }
        do {
            for suffix in ["", "-wal", "-shm"] {
                let from = URL(filePath: legacy.path(percentEncoded: false) + suffix)
                guard fm.fileExists(atPath: from.path(percentEncoded: false)) else { continue }
                try fm.moveItem(at: from, to: URL(filePath: target.path(percentEncoded: false) + suffix))
            }
            log.info("Moved the legacy store to \(target.lastPathComponent, privacy: .public)")
            return true
        } catch {
            log.error("Moving the legacy store failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func makeContainer() -> ModelContainer {
        #if DEBUG
        // `-debugEmptyStore 1`: an empty in-memory store (first-launch screenshots without
        // wiping the saved games).
        if UserDefaults.standard.string(forKey: "debugEmptyStore") != nil {
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: memory)
        }
        #endif
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        #if CLOUDKIT_SYNC
        let inTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !inTests {
            let url = storeURL(.cloud)
            migrateLegacyStore(to: url)
            do {
                let config = ModelConfiguration("cloud", schema: schema, url: url, cloudKitDatabase: .private(containerID))
                let container = try ModelContainer(for: schema, configurations: config)
                isSyncing = true
                return container
            } catch {
                // The cloud file stays untouched for the next launch; this session is local.
                log.error("CloudKit store unavailable, using the local store: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
        do {
            let url = storeURL(.local)
            // The XCTest host shares the app's container: it never adopts the user's store.
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil { migrateLegacyStore(to: url) }
            let config = ModelConfiguration("local", schema: schema, url: url, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            // Last resort: keep the app usable this session rather than crash.
            log.fault("Local store failed, using memory: \(error.localizedDescription, privacy: .public)")
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: memory)
        }
    }
}
