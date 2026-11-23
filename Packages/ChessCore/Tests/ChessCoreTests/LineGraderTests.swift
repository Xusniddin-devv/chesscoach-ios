import Foundation
import Testing
@testable import ChessCore

private func request(_ moves: [String]) -> AnalysisRequest {
    AnalysisRequest(startFen: Rules.startFen, moves: moves, depth: 14, multiPV: 2)
}

@MainActor
private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(3)
    while !condition() {
        if clock.now >= deadline { return false }
        await Task.yield()
    }
    return true
}

@MainActor
private func settle() async {
    for _ in 0..<500 { await Task.yield() }
}

@MainActor @Test func lineGraderGradesInOrderWithOwnHistory() async {
    let line = ["e2e4", "e7e5", "g1f3"]
    let engine = FakeEngine()
    engine.analysisGate.close()
    let grader = LineGrader(engine: engine)
    for i in line.indices {
        #expect(grader.enqueue(history: Array(line.prefix(i)), uci: line[i]))
    }
    #expect(grader.pendingCount == 3)
    // Held on the first grade's first search: nothing else may start meanwhile.
    #expect(await eventually { engine.analysisGate.waiterCount == 1 })
    await settle()
    #expect(engine.requests == [request([])])

    engine.analysisGate.open()
    #expect(await eventually { grader.verdicts.count == 3 })
    #expect(grader.pendingCount == 0)
    #expect(engine.requests == [request([]), request(["e2e4"]),
                                request(["e2e4"]), request(["e2e4", "e7e5"]),
                                request(["e2e4", "e7e5"]), request(line)])
    #expect(grader.verdicts[1]?.san == "e4")
    #expect(grader.verdicts[2]?.mover == .black)
    #expect(grader.verdicts[3]?.uci == "g1f3")
}

@MainActor @Test func lineGraderResetDropsLateGradesWithoutError() async {
    let engine = FakeEngine()
    engine.analysisGate.close()
    let grader = LineGrader(engine: engine)
    grader.enqueue(history: [], uci: "e2e4")
    grader.enqueue(history: ["e2e4"], uci: "e7e5")
    #expect(await eventually { engine.analysisGate.waiterCount == 1 })

    grader.reset()  // cancels the running grade: the engine throws CancellationError
    engine.analysisGate.open()
    await settle()
    #expect(grader.verdicts.isEmpty)
    #expect(grader.pendingCount == 0)
    #expect(grader.hasError == false)
}

@MainActor @Test func lineGraderLateResultOfOldGenerationIsDropped() async {
    // An engine that ignores cancellation still answers; the answer must not land.
    let engine = FakeEngine(honorsCancellation: false)
    engine.analysisGate.close()
    let grader = LineGrader(engine: engine)
    grader.enqueue(history: [], uci: "e2e4")
    #expect(await eventually { engine.analysisGate.waiterCount == 1 })
    grader.reset()
    engine.analysisGate.open()
    await settle()
    #expect(grader.verdicts.isEmpty)
}

@MainActor @Test func lineGraderDiscardKeepsEarlierPlies() async {
    let engine = FakeEngine()
    let grader = LineGrader(engine: engine)
    grader.enqueue(history: [], uci: "e2e4")
    grader.enqueue(history: ["e2e4"], uci: "e7e5")
    #expect(await eventually { grader.verdicts.count == 2 })

    grader.discard(after: 1)
    #expect(grader.verdicts.keys.sorted() == [1])
    grader.enqueue(history: ["e2e4"], uci: "c7c5")
    #expect(await eventually { grader.verdicts.count == 2 })
    #expect(grader.verdicts[2]?.san == "c5")
}

@MainActor @Test func lineGraderDiscardWithNothingLaterKeepsTheRunningGrade() async {
    let engine = FakeEngine()
    engine.analysisGate.close()
    let grader = LineGrader(engine: engine)
    grader.enqueue(history: [], uci: "e2e4")
    #expect(await eventually { engine.analysisGate.waiterCount == 1 })
    grader.discard(after: 1)
    engine.analysisGate.open()
    #expect(await eventually { grader.verdicts.count == 1 })
    #expect(engine.requests == [request([]), request(["e2e4"])])
}

@MainActor @Test func lineGraderEngineErrorWaitsForRetry() async {
    let engine = FakeEngine()
    engine.failNextAnalyze()
    let grader = LineGrader(engine: engine)
    grader.enqueue(history: [], uci: "e2e4")
    #expect(await eventually { grader.hasError })
    #expect(grader.pendingCount == 1)
    #expect(grader.verdicts.isEmpty)

    grader.retry()
    #expect(await eventually { grader.verdicts.count == 1 })
    #expect(grader.hasError == false)
}

@MainActor @Test func lineGraderRejectsIllegalMoves() {
    let grader = LineGrader(engine: FakeEngine())
    #expect(grader.enqueue(history: [], uci: "e2e5") == false)
    #expect(grader.enqueue(history: ["e2e5"], uci: "e7e5") == false)
    #expect(grader.pendingCount == 0)
}

@MainActor @Test func lineGraderUsesItsStartFen() async {
    let fen = "4k3/8/8/8/8/8/4P3/4K3 b - - 0 1"
    let engine = FakeEngine()
    let grader = LineGrader(engine: engine, startFen: fen)
    grader.enqueue(history: [], uci: "e8d7")
    #expect(await eventually { grader.verdicts.count == 1 })
    #expect(grader.verdicts[1]?.mover == .black)
    #expect(engine.requests.first?.startFen == fen)
}
