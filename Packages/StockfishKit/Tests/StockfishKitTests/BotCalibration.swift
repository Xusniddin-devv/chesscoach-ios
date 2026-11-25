import ChessCore
import Foundation
@testable import StockfishKit
import Testing

extension GlobalEngineSuite {
    /// Measurement only (`BOT_CALIBRATION=1 swift test --filter BotCalibration`): each ladder bot
    /// plays itself from a few openings; every move's centipawn loss is measured at depth 12.
    /// Prints average centipawn loss (ACPL) and blunder rate per bot. Human reference ACPL,
    /// rapid: about 120+ at 600, 90 at 800, 70 at 1000, 55 at 1300, 45 at 1600, 35 at 1900,
    /// 25 at 2300 (rough, from published rating/ACPL studies).
    @Suite(.enabled(if: ProcessInfo.processInfo.environment["BOT_CALIBRATION"] == "1"))
    struct BotCalibration {
        static let openings: [[String]] = [
            ["e2e4", "e7e5"], ["d2d4", "d7d5"], ["e2e4", "c7c5"], ["c2c4", "e7e5"],
            ["g1f3", "d7d5"], ["e2e4", "e7e6"],
        ]

        @Test func measureLadder() async throws {
            let e = StockfishEngine.shared
            var report: [String] = []
            for bot in Bot.all {
                var losses: [Int] = []
                for opening in Self.openings {
                    var moves = opening
                    for _ in 0..<40 {
                        guard let fen = Rules.fen(startFen: Rules.startFen, moves: moves),
                              !Rules.legalMoves(fen: fen).isEmpty else { break }
                        let before = try await e.analyze(.init(startFen: Rules.startFen, moves: moves, depth: 12, multiPV: 1))
                        let uci = try await e.opponentMove(startFen: Rules.startFen, moves: moves, elo: bot.elo)
                        guard !uci.isEmpty else { break }
                        let after = try await e.analyze(.init(startFen: Rules.startFen, moves: moves + [uci], depth: 12, multiPV: 1))
                        // Both scores from the mover's view: before as side to move, after negated.
                        let s = min(max(toCp(before.lines.first?.score ?? Score(cp: 0), sideToMove: .white), -1000), 1000)
                        let c = min(max(-toCp(after.lines.first?.score ?? Score(cp: 0), sideToMove: .white), -1000), 1000)
                        losses.append(Int(max(0, s - c)))
                        moves.append(uci)
                    }
                }
                let acpl = Double(losses.reduce(0, +)) / Double(max(losses.count, 1))
                let blunders = Double(losses.filter { $0 >= 300 }.count) / Double(max(losses.count, 1))
                report.append(String(format: "%@ (%d): ACPL %.0f, blunders(≥300cp) %.1f%%, moves %d",
                                     bot.name, bot.elo, acpl, blunders * 100, losses.count))
            }
            print("BOT CALIBRATION\n" + report.joined(separator: "\n"))
        }
    }
}
