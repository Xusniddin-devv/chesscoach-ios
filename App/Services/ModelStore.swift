import Foundation
import SwiftData
import OSLog

/// The SwiftData container. With `CLOUDKIT_SYNC` (Config/App.xcconfig) the store always
/// opens with CloudKit mirroring to the private database (`iCloud.uz.xq.chessc`): it works
/// without an iCloud account and starts syncing once one exists. It is never toggled on the
/// account state, because a mirrored store reopened without mirroring can open read-only or
/// be purged. The CloudKit and local configurations use separate files (`cloud.store`,
/// `local.store`), so the fallback never opens the mirrored file. The legacy `default.store`
/// is copied to the store being opened and deleted only once that store has opened. Models must stay
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

    private static let storeSuffixes = ["", "-wal", "-shm"]

    private static func files(of store: URL) -> [URL] {
        storeSuffixes.map { URL(filePath: store.path(percentEncoded: false) + $0) }
    }

    /// Builds before separate files kept everything in SwiftData's `default.store`. Copies it
    /// (with its -wal / -shm files, all or nothing) to `target` when `target` doesn't exist
    /// yet. The original stays until the container on `target` has opened
    /// (`finishLegacyMigration`); if it doesn't open, `undoLegacyMigration` removes the copy
    /// and the next store can take it. Returns whether it copied.
    @discardableResult
    static func migrateLegacyStore(to target: URL, in directory: URL = .applicationSupportDirectory) -> Bool {
        let fm = FileManager.default
        let legacy = directory.appending(path: "default.store")
        guard fm.fileExists(atPath: legacy.path(percentEncoded: false)),
              !fm.fileExists(atPath: target.path(percentEncoded: false)) else { return false }
        do {
            for (from, to) in zip(files(of: legacy), files(of: target))
            where fm.fileExists(atPath: from.path(percentEncoded: false)) {
                try fm.copyItem(at: from, to: to)
            }
            log.info("Copied the legacy store to \(target.lastPathComponent, privacy: .public)")
            return true
        } catch {
            log.error("Copying the legacy store failed: \(error.localizedDescription, privacy: .public)")
            undoLegacyMigration(target)
            return false
        }
    }

    /// The container on the copy opened: the original store goes.
    static func finishLegacyMigration(in directory: URL = .applicationSupportDirectory) {
        for file in files(of: directory.appending(path: "default.store")) { try? FileManager.default.removeItem(at: file) }
    }

    /// The container on the copy didn't open: remove the copy, keep the original.
    static func undoLegacyMigration(_ target: URL) {
        for file in files(of: target) { try? FileManager.default.removeItem(at: file) }
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
            let copied = migrateLegacyStore(to: url)
            do {
                let config = ModelConfiguration("cloud", schema: schema, url: url, cloudKitDatabase: .private(containerID))
                let container = try ModelContainer(for: schema, configurations: config)
                if copied { finishLegacyMigration() }
                isSyncing = true
                return container
            } catch {
                // The cloud file stays for the next launch (a fresh copy of the legacy store is
                // removed again, so the local store can take it); this session is local.
                if copied { undoLegacyMigration(url) }
                log.fault("CloudKit store unavailable, using the local store this session: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
        do {
            let url = storeURL(.local)
            // The XCTest host shares the app's container: it never adopts the user's store.
            let copied = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil && migrateLegacyStore(to: url)
            let config = ModelConfiguration("local", schema: schema, url: url, cloudKitDatabase: .none)
            do {
                let container = try ModelContainer(for: schema, configurations: config)
                if copied { finishLegacyMigration() }
                return container
            } catch {
                if copied { undoLegacyMigration(url) }
                throw error
            }
        } catch {
            // Last resort: keep the app usable this session rather than crash.
            log.fault("Local store failed, using memory: \(error.localizedDescription, privacy: .public)")
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: memory)
        }
    }
}
