import Testing
import SwiftData
import Foundation
import ChessCore
@testable import ChessCoach

/// The final-review fixes around persistence: the decode cache, sync duplicates, re-import
/// merging, separate store files, the privacy manifest, the Pro gate on habits, voice input.
@MainActor
struct SyncAndStoreTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(
            for: ModelStore.schema,
            configurations: ModelConfiguration(schema: ModelStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    private func game(_ id: UUID = UUID(), moves: [String] = ["e2e4", "e7e5"], pass: AnalysisPass? = nil,
                      result: GameResult = .whiteWins) -> GameSnapshot {
        let analysis = pass.map {
            GameAnalysis(depth: 14, verdicts: [], whiteWin: [], accuracyWhite: 80, accuracyBlack: 70, pass: $0)
        }
        return GameSnapshot(id: id, date: Date(timeIntervalSince1970: 1_800_000_000), botId: "chesscom",
                            userColor: .white, mode: .silent, startFen: Rules.startFen, moves: moves,
                            sans: [], result: result, verdicts: [], analysisVersion: 1, playerRatingUsed: 900,
                            analysis: analysis, source: "chesscom", opponentName: "opp", opponentRating: 1000)
    }

    @discardableResult
    private func insert(_ snapshot: GameSnapshot) throws -> GameRecord {
        let record = try GameRecord(snapshot: snapshot)
        context.insert(record)
        try context.save()
        return record
    }

    // MARK: Decode cache (I3)

    @Test func cachedSnapshotFollowsUpdates() throws {
        let record = try insert(game())
        #expect(record.snapshot?.analysis == nil)
        #expect(record.finalFen == Rules.apply(uci: "e7e5", to: Rules.apply(uci: "e2e4", to: Rules.startFen)!.fenAfter)!.fenAfter)
        var analysed = try #require(record.snapshot)
        analysed.analysis = GameAnalysis(depth: 14, verdicts: [], whiteWin: [], accuracyWhite: 1, accuracyBlack: 2)
        analysed.moves = ["d2d4"]
        try record.update(analysed)
        #expect(record.revision == 1)
        #expect(record.snapshot?.analysis?.accuracyWhite == 1)
        #expect(record.finalFen == Rules.apply(uci: "d2d4", to: Rules.startFen)!.fenAfter)
    }

    @Test func fingerprintChangesWithRewrites() throws {
        let record = try insert(game())
        let before = GameRecord.fingerprint([record])
        try record.update(game(record.id, moves: ["d2d4"]))
        #expect(GameRecord.fingerprint([record]) != before)
    }

    // MARK: Sync duplicates (I4)

    @Test func syncCopiesCountOnceAndMergeKeepsTheFullAnalysis() throws {
        let id = UUID()
        try insert(game(id))
        try insert(game(id, pass: .full))
        try insert(game(id, pass: .quick))
        try insert(game(result: .blackWins))
        let records = try context.fetch(FetchDescriptor<GameRecord>())
        #expect(records.count == 4)

        // Readers see one copy of each game, so ForEach ids stay unique.
        let profile = ProfileModel(records: records)
        #expect(profile.games.count == 2)
        #expect(Set(profile.games.map(\.id)).count == 2)
        #expect(profile.games.first { $0.id == id }?.snapshot.analysis?.isFull == true)
        #expect(HomeView.recentGames(records).count == 2)

        // The merge pass deletes the extras and keeps the fully analysed copy.
        #expect(GameRecord.mergeDuplicates(in: context) == 2)
        let left = try context.fetch(FetchDescriptor<GameRecord>())
        #expect(left.count == 2)
        #expect(left.first { $0.id == id }?.snapshot?.analysis?.isFull == true)
        #expect(GameRecord.mergeDuplicates(in: context) == 0)
    }

    /// A re-import updates games in place and keeps a stored full analysis (M14).
    @Test func reimportKeepsFullAnalyses() throws {
        let id = UUID()
        ProfileStore.saveGames([game(id)], in: context)
        let record = try #require(try context.fetch(FetchDescriptor<GameRecord>()).first)
        try record.update(game(id, pass: .full))
        try context.save()
        ProfileStore.saveGames([game(id), game()], in: context)
        let rows = try context.fetch(FetchDescriptor<GameRecord>())
        #expect(rows.count == 2)
        #expect(rows.first { $0.id == id }?.snapshot?.analysis?.isFull == true)
        #expect(rows.first { $0.id == id } === record)  // same row, not delete + insert
    }

    // MARK: Store files (I7)

    @Test func cloudAndLocalUseSeparateFiles() {
        #expect(ModelStore.storeURL(.cloud).lastPathComponent == "cloud.store")
        #expect(ModelStore.storeURL(.local).lastPathComponent == "local.store")
    }

    @Test func legacyStoreMovesOnce() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("db".utf8).write(to: dir.appending(path: "default.store"))
        try Data("wal".utf8).write(to: dir.appending(path: "default.store-wal"))
        let target = ModelStore.storeURL(.local, in: dir)
        #expect(ModelStore.migrateLegacyStore(to: target, in: dir))
        #expect(try Data(contentsOf: target) == Data("db".utf8))
        #expect(try Data(contentsOf: dir.appending(path: "local.store-wal")) == Data("wal".utf8))
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "default.store").path(percentEncoded: false)))
        // An existing target is never overwritten.
        try Data("new".utf8).write(to: dir.appending(path: "default.store"))
        #expect(!ModelStore.migrateLegacyStore(to: target, in: dir))
        #expect(try Data(contentsOf: target) == Data("db".utf8))
    }

    @Test func savesReportSuccess() throws {
        try insert(game())
        #expect(context.saveReporting("a test game"))
        #expect(SaveIssues.shared.failed == nil)
    }

    // MARK: Privacy manifest (C1)

    @Test func privacyManifestIsBundled() throws {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        let types = (plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []).compactMap { $0["NSPrivacyAccessedAPIType"] as? String }
        #expect(types.contains("NSPrivacyAccessedAPICategoryUserDefaults"))
        #expect(types.contains("NSPrivacyAccessedAPICategoryFileTimestamp"))
    }

    // MARK: Pro gates (I5) and voice (I6)

    @Test func freeUsersSeeTheTopHabitAndATeaser() {
        let free = WeaknessAllowance.split([1, 2, 3, 4], isPro: false)
        #expect(free.open == [1] && free.locked == [2, 3])
        let pro = WeaknessAllowance.split([1, 2, 3, 4], isPro: true)
        #expect(pro.open == [1, 2, 3] && pro.locked.isEmpty)
        #expect(WeaknessAllowance.split([1], isPro: false).locked.isEmpty)
        #expect(!ProFeature.allCases.map(\.rawValue).contains("liveGrading"))
    }

    @Test func micFormatWithoutChannelsIsRefused() {
        #expect(!VoiceInput.isUsable(channels: 0, sampleRate: 44_100))
        #expect(!VoiceInput.isUsable(channels: 1, sampleRate: 0))
        #expect(VoiceInput.isUsable(channels: 1, sampleRate: 48_000))
    }
}
