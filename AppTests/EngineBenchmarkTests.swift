import Testing
import ChessCore
import StockfishKit
@testable import ChessCoach

/// Uses the process-wide engine, so it runs alone in its suite.
@Suite(.serialized) struct EngineBenchmarkTests {
    @Test func cancellingTheRunRestoresDefaultConfiguration() async throws {
        let engine = StockfishEngine.shared
        let run = Task { try await EngineBenchmark.run(threadCounts: [4]) }
        while await engine.currentConfiguration.threads != 4 { try await Task.sleep(for: .milliseconds(5)) }
        run.cancel()
        await #expect(throws: CancellationError.self) { try await run.value }

        let config = await engine.currentConfiguration
        #expect(config.threads == EngineHub.defaultThreads && config.hashMB == EngineHub.defaultHashMB)
        // The engine is usable afterwards and searches with the defaults.
        let r = try await engine.analyze(.init(startFen: Rules.startFen, moves: ["e2e4"], depth: 4, multiPV: 1))
        #expect(!r.bestMove.isEmpty)
    }
}
