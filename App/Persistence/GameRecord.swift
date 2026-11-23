import Foundation
import SwiftData
import ChessCore

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

    var snapshot: GameSnapshot? { try? decodeSnapshot(snapshotData) }
}
