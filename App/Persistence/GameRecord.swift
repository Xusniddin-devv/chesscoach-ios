import Foundation
import OSLog
import Synchronization
import SwiftData
import ChessCore

private let log = Logger(subsystem: "uz.xq.chessc", category: "persistence")

/// CloudKit-compatible: every stored property has a default, nothing is unique.
@Model
final class GameRecord {
    var id: UUID = UUID()
    var date: Date = Date.now
    var snapshotData: Data = Data()
    /// Bumped by every `update`; with the id and byte count it keys the decode cache, so a
    /// screen reading `snapshot` on every render decodes each game once.
    var revision: Int = 0

    init(snapshot: GameSnapshot) throws {
        id = snapshot.id
        date = snapshot.date
        snapshotData = try encodeSnapshot(snapshot)
    }

    /// Replaces the stored game in place (same record, same id), e.g. to add its analysis.
    /// The caller saves the context.
    func update(_ snapshot: GameSnapshot) throws {
        snapshotData = try encodeSnapshot(snapshot)
        revision += 1
    }

    /// The stored game, or nil (logged once) if its data cannot be decoded. Decoding is
    /// lenient, so nil means the game itself is unreadable, not just one of its verdicts.
    /// Memoised (`GameCache`).
    var snapshot: GameSnapshot? { GameCache.shared.entry(for: self).snapshot }

    /// The final position, memoised.
    var finalFen: String {
        GameCache.shared.derived(for: self, \.finalFen) { snapshot in
            var fen = snapshot?.startFen ?? Rules.startFen
            for uci in snapshot?.moves ?? [] {
                guard let applied = Rules.apply(uci: uci, to: fen) else { break }
                fen = applied.fenAfter
            }
            return fen
        }
    }

    /// Puzzles made from the user's mistakes in this game, memoised.
    var blunderPuzzles: [Puzzle] {
        GameCache.shared.derived(for: self, \.puzzles) { snapshot in
            snapshot.map(BlunderPuzzles.from(snapshot:)) ?? []
        }
    }

    fileprivate func decode() -> GameSnapshot? {
        do {
            return try decodeSnapshot(snapshotData)
        } catch {
            log.error("Game \(self.id, privacy: .public) is unreadable (\(self.snapshotData.count) bytes): \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

/// Decoded games and what is derived from them (final position, own-mistake puzzles), by
/// record id + revision + byte count. Lists on Home, Profile, Puzzles and Learn read
/// `snapshot` on every render; without this each render JSON-decoded every saved game.
final class GameCache: Sendable {
    static let shared = GameCache()

    fileprivate struct Key: Hashable {
        let id: UUID
        let revision: Int
        let size: Int
    }

    fileprivate struct Entry {
        let snapshot: GameSnapshot?
        var finalFen: String?
        var puzzles: [Puzzle]?
    }

    /// Enough for every game of a heavy user plus edits; past it the cache starts over.
    private static let capacity = 2_000
    private let entries = Mutex<[Key: Entry]>([:])

    fileprivate func entry(for record: GameRecord) -> Entry {
        let key = Key(id: record.id, revision: record.revision, size: record.snapshotData.count)
        if let hit = entries.withLock({ $0[key] }) { return hit }
        let entry = Entry(snapshot: record.decode())
        entries.withLock {
            if $0.count >= Self.capacity { $0.removeAll(keepingCapacity: true) }
            $0[key] = entry
        }
        return entry
    }

    fileprivate func derived<T>(for record: GameRecord, _ path: WritableKeyPath<Entry, T?>,
                                make: (GameSnapshot?) -> T) -> T {
        let key = Key(id: record.id, revision: record.revision, size: record.snapshotData.count)
        let current = entry(for: record)
        if let value = current[keyPath: path] { return value }
        let value = make(current.snapshot)
        entries.withLock { $0[key]?[keyPath: path] = value }
        return value
    }
}

// MARK: - Sync duplicates

extension GameRecord {
    /// One record per game: CloudKit can leave two rows with the same stable id (a re-import
    /// on a second phone, two devices saving one game). Keeps `GameDedupe.keeper`'s pick and
    /// the order of `records` otherwise (pass them newest first).
    static func unique(_ records: [GameRecord]) -> [GameRecord] {
        var seen = Set<UUID>()
        guard records.contains(where: { !seen.insert($0.id).inserted }) else { return records }
        let keep = Set(keepers(records).map(ObjectIdentifier.init))
        return records.filter { keep.contains(ObjectIdentifier($0)) }
    }

    /// Changes whenever a game is added, removed or rewritten; a cheap `.task(id:)` key that
    /// doesn't touch the game data.
    static func fingerprint(_ records: [GameRecord]) -> Int {
        var hasher = Hasher()
        hasher.combine(records.count)
        for record in records {
            hasher.combine(record.id)
            hasher.combine(record.revision)
        }
        return hasher.finalize()
    }

    /// Deletes the extra copies of every duplicated game (at launch and when a remote change
    /// arrives). Returns how many rows were removed.
    @MainActor @discardableResult
    static func mergeDuplicates(in context: ModelContext) -> Int {
        // Ids only first: the common case (no copies) never loads the game data.
        var idsOnly = FetchDescriptor<GameRecord>()
        idsOnly.propertiesToFetch = [\.id]
        let ids = ((try? context.fetch(idsOnly)) ?? []).map(\.id)
        guard Set(ids).count < ids.count else { return 0 }
        let all = (try? context.fetch(FetchDescriptor<GameRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let keep = Set(keepers(all).map(ObjectIdentifier.init))
        let extras = all.filter { !keep.contains(ObjectIdentifier($0)) }
        guard !extras.isEmpty else { return 0 }
        extras.forEach(context.delete)
        context.saveReporting("merging synced games")
        log.info("Merged \(extras.count) duplicate games")
        return extras.count
    }

    /// The record kept for each id: readable copies first, then `GameDedupe`'s rule.
    private static func keepers(_ records: [GameRecord]) -> [GameRecord] {
        var groups: [UUID: [GameRecord]] = [:]
        var order: [UUID] = []
        for record in records {
            if groups[record.id] == nil { order.append(record.id) }
            groups[record.id, default: []].append(record)
        }
        return order.compactMap { id in
            let copies = groups[id] ?? []
            guard copies.count > 1 else { return copies.first }
            let readable = copies.compactMap { record in record.snapshot.map { (record, $0) } }
            guard !readable.isEmpty else { return copies.first }
            return GameDedupe.keeper(readable.map(\.1)).map { readable[$0].0 }
        }
    }
}
