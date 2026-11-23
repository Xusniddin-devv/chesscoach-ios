import StockfishCore
import StockfishKit
import Testing

/// The bridge drives one global engine, so these run one at a time.
@Suite(.serialized)
struct BridgeTests {
    @Test func uciHandshake() async throws {
        let lines = try await BridgeHarness.run(["uci"], until: { $0 == "uciok" })
        #expect(lines.contains { $0.hasPrefix("id name Stockfish 18") })
    }

    @Test func searchesWithNetsLoaded() async throws {
        let (big, small) = StockfishResources.netPaths()
        let lines = try await BridgeHarness.run([
            "uci", "setoption name EvalFile value \(big)", "setoption name EvalFileSmall value \(small)",
            "isready", "position startpos", "go depth 8",
        ], until: { $0.hasPrefix("bestmove") })
        #expect(lines.contains { $0.hasPrefix("info string NNUE evaluation using \(big)") })
        #expect(lines.last!.split(separator: " ")[1].count >= 4)
    }

    @Test func restartAfterQuit() async throws {
        _ = try await BridgeHarness.run(["uci"], until: { $0 == "uciok" })  // harness calls sf_quit at end
        _ = try await BridgeHarness.run(["uci"], until: { $0 == "uciok" })
    }

    @Test func versionNamesStockfish18() {
        #expect(String(cString: sf_version()) == "Stockfish 18")
    }
}
