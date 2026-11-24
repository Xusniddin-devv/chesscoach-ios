import Foundation
import Testing
@testable import ChessCore

/// Sync can leave two rows for one game (same stable id); one copy is kept.
@Suite struct GameDedupeTests {
    private func copy(_ id: UUID, moves: Int = 2, pass: AnalysisPass? = nil) -> GameSnapshot {
        let analysis = pass.map {
            GameAnalysis(depth: 14, verdicts: [], whiteWin: [], accuracyWhite: 80, accuracyBlack: 70, pass: $0)
        }
        return GameSnapshot(id: id, date: .now, botId: "chesscom", userColor: .white, mode: .silent,
                            startFen: Rules.startFen, moves: Array(repeating: "e2e4", count: moves),
                            sans: [], result: .whiteWins, verdicts: [], analysisVersion: 1,
                            playerRatingUsed: 900, analysis: analysis, source: "chesscom")
    }

    @Test func fullAnalysisBeatsQuickBeatsNone() {
        let id = UUID()
        #expect(GameDedupe.keeper([copy(id), copy(id, pass: .quick), copy(id, pass: .full)]) == 2)
        #expect(GameDedupe.keeper([copy(id), copy(id, pass: .quick)]) == 1)
    }

    @Test func tiesKeepTheFirstCopy() {
        let id = UUID()
        #expect(GameDedupe.keeper([copy(id, pass: .full), copy(id, pass: .full)]) == 0)
        #expect(GameDedupe.keeper([copy(id), copy(id)]) == 0)
        // An analysis-board line that grew on one device: the longer copy wins.
        #expect(GameDedupe.keeper([copy(id, moves: 2), copy(id, moves: 5)]) == 1)
        #expect(GameDedupe.keeper([]) == nil)
    }

    /// Which row survives must not depend on content (it can differ between devices mid-sync)
    /// or on fetch order: the smallest row id, the same on every device.
    @Test func survivorIsTheSmallestRowIdInAnyOrder() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let b = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000000")!
        #expect(GameDedupe.survivor(rowIDs: [a, b]) == 0)
        #expect(GameDedupe.survivor(rowIDs: [b, a]) == 1)
        // Copies that share a row id can't be told apart the same way everywhere: keep all.
        #expect(GameDedupe.survivor(rowIDs: [a, a, b]) == nil)
        #expect(GameDedupe.survivor(rowIDs: []) == nil)
    }
}
