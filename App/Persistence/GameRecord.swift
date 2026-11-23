import Foundation
import OSLog
import SwiftData
import ChessCore

private let log = Logger(subsystem: "uz.xq.chessc", category: "persistence")

/// CloudKit-compatible: every stored property has a default, nothing is unique.
@Model
final class GameRecord {
    var id: UUID = UUID()
    var date: Date = Date.now
    var snapshotData: Data = Data()

    init(snapshot: GameSnapshot) throws {
        id = snapshot.id
        date = snapshot.date
        snapshotData = try encodeSnapshot(snapshot)
    }

    /// The stored game, or nil (logged) if its data cannot be decoded. Decoding is lenient, so
    /// nil means the game itself is unreadable, not just one of its verdicts.
    var snapshot: GameSnapshot? {
        do {
            return try decodeSnapshot(snapshotData)
        } catch {
            log.error("Game \(self.id, privacy: .public) is unreadable (\(self.snapshotData.count) bytes): \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
