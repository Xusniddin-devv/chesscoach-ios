import Testing
import Foundation
@testable import ChessCore

private func game(_ moves: [String], id: UUID = UUID(), user: Piece.Color = .white) -> GameSnapshot {
    GameSnapshot(id: id, date: .now, botId: "lichess", userColor: user, mode: .silent, startFen: Rules.startFen,
                 moves: moves, sans: [], result: .whiteWins, verdicts: [], analysisVersion: 1, playerRatingUsed: 900,
                 source: "lichess", opponentName: "opp")
}

/// Ruy Lopez: 1.e4 e5 2.Nf3 Nc6 3.Bb5 a6 are all book; 4.h4?! leaves it.
private let ruyThenOut = ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6", "h2h4", "g8f6"]

/// Knights shuffling out and back: legal forever, never in the book after the first ply pair.
private func shuffle(_ plies: Int) -> [String] {
    let cycle = ["g1f3", "g8f6", "f3g1", "f6g8"]
    return (0..<plies).map { cycle[$0 % 4] }
}

@Suite struct AnalysisPlanTests {
    @Test func quickSkipsBookPliesAndUsesNodes() throws {
        let plan = try AnalysisPlan(startFen: Rules.startFen, moves: ruyThenOut, mode: .quick(nodes: 30_000, maxPly: 120))
        #expect(plan.bookPlies == 6)
        // Only the last book position and everything after it are searched.
        #expect(plan.positions == [6, 7, 8])
        let request = plan.request(for: 7)
        #expect(request.nodes == 30_000 && request.multiPV == 1)
        #expect(request.moves == Array(ruyThenOut.prefix(7)))
        #expect(request.cacheKey.hasPrefix("n30000|"))
    }

    @Test func quickStopsAtThePlyCap() throws {
        let moves = shuffle(130)
        let plan = try AnalysisPlan(startFen: Rules.startFen, moves: moves, mode: .quick(nodes: 1000, maxPly: 120))
        #expect(plan.plies == 120)
        #expect(plan.positions.last == 120)
        let analysis = plan.assemble(Dictionary(uniqueKeysWithValues: plan.positions.map {
            ($0, AnalysisResult(bestMove: "", lines: [PVLine(multipv: 1, depth: 9, score: Score(cp: 0), pv: [])]))
        }))
        #expect(analysis.verdicts.count == 120)
        #expect(analysis.whiteWin.count == 121)
        #expect(analysis.pass == .quick && analysis.nodes == 1000 && analysis.depth == 9)
        #expect(!analysis.isFull)
    }

    @Test func quickGradesBookPliesAsBookAndFindsTheBlunderAfter() throws {
        let plan = try AnalysisPlan(startFen: Rules.startFen, moves: ruyThenOut, mode: .quick(nodes: 1000, maxPly: 120))
        // Position 6 (White to move) +30; after 4.h4 Black is better by 400; after ...Nf6 still -400.
        let results: [Int: AnalysisResult] = [
            6: AnalysisResult(bestMove: "e1g1", lines: [PVLine(multipv: 1, depth: 8, score: Score(cp: 30), pv: ["e1g1"])]),
            7: AnalysisResult(bestMove: "g8f6", lines: [PVLine(multipv: 1, depth: 8, score: Score(cp: 400), pv: [])]),
            8: AnalysisResult(bestMove: "", lines: [PVLine(multipv: 1, depth: 8, score: Score(cp: -400), pv: [])]),
        ]
        let a = plan.assemble(results)
        #expect(a.verdicts.prefix(6).allSatisfy { $0.classification == .book })
        #expect(a.verdicts[6].classification == .blunder)
        // Book positions share the last book position's score.
        #expect(abs(a.whiteWin[0] - a.whiteWin[6]) < 0.01)
    }

    @Test func fullSearchesEveryPositionAtDepth14MultiPV2() throws {
        let plan = try AnalysisPlan(startFen: Rules.startFen, moves: ruyThenOut, mode: AnalysisPlan.full)
        #expect(plan.bookPlies == 0 && plan.positions == Array(0...8))
        let r = plan.request(for: 3)
        #expect(r.depth == 14 && r.multiPV == 2 && r.nodes == nil)
        #expect(plan.assemble([:]).pass == .full)
    }

    @Test func storedAnalysisPassDecodesLeniently() throws {
        let a = GameAnalysis(depth: 14, verdicts: [], whiteWin: [50], accuracyWhite: 90, accuracyBlack: 80)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as! [String: Any]
        json.removeValue(forKey: "pass")
        let old = try JSONDecoder().decode(GameAnalysis.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.pass == .full)  // stored before quick passes existed
        json["pass"] = "turbo"
        let unknown = try JSONDecoder().decode(GameAnalysis.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(unknown.pass == .quick)  // not trusted as full

        var g = game(["e2e4"])
        #expect(g.needsFullAnalysis)
        g.analysis = GameAnalysis(depth: 0, verdicts: [], whiteWin: [50], accuracyWhite: 1, accuracyBlack: 1, pass: .quick, nodes: 10)
        #expect(g.needsFullAnalysis)
        g.platformAccuracy = PlatformAccuracy(white: 77.5, black: nil, source: "chesscom")
        let decoded = try decodeSnapshot(encodeSnapshot(g))
        #expect(decoded.analysis?.pass == .quick && decoded.analysis?.nodes == 10)
        #expect(decoded.platformAccuracy == g.platformAccuracy)
        #expect(decoded.userAccuracy == 77.5)
        g.analysis?.pass = .full
        #expect(!g.needsFullAnalysis)
    }
}

@Suite struct PlatformEvalTests {
    private func lichessGames() throws -> [ImportedGame] {
        LichessClient.parseNDJSON(try fixture("lichess-games-evals.ndjson"), limit: 20)
    }

    @Test func lichessEvalsAndAccuracyDecode() throws {
        let games = try lichessGames()
        #expect(games.count == 4)
        #expect(games[0].evals?.count == 36)
        #expect(games[0].accuracy == PlatformAccuracy(white: 62, black: 98, source: "lichess"))
        #expect(games[2].evals == nil && games[2].accuracy == nil)  // never analysed on Lichess
        #expect(games[0].evals?.contains { $0.best != nil && $0.variation != nil } == true)
    }

    @Test func completeEvalsBecomeAQuickAnalysisMarkedLichess() throws {
        let games = try lichessGames()
        let s = try PGNImporter.snapshot(game: games[0], username: "DrNykterstein", platform: .lichess)
        let a = try #require(s.analysis)
        #expect(a.pass == .quick && a.evalSource == "lichess")
        #expect(a.verdicts.count == s.moves.count)
        #expect(a.whiteWin.count == s.moves.count + 1)
        // Lichess judged one blunder in this game (Black's opponent, White): our rules agree it is bad.
        let worst = try #require(a.verdicts.max { $0.winDrop < $1.winDrop })
        #expect(worst.mover == .white && worst.classification.isNegative)
        #expect(s.platformAccuracy?.black == 98)
        #expect(s.userAccuracy == 98)
    }

    @Test func mateEndingGameMissesOnlyTheFinalEvalAndStillCounts() throws {
        let games = try lichessGames()
        #expect(games[1].evals?.count == 48)
        let s = try PGNImporter.snapshot(game: games[1], username: "DrNykterstein", platform: .lichess)
        let a = try #require(s.analysis)
        #expect(s.moves.count == 49 && a.verdicts.count == 49)
        #expect(a.whiteWin.last ?? 0 > 99)  // White mated Black
    }

    @Test func incompleteEvalsAreIgnored() throws {
        let games = try lichessGames()
        let s = try PGNImporter.snapshot(game: games[3], username: "DrNykterstein", platform: .lichess)
        #expect(s.analysis == nil)
        #expect(s.platformAccuracy != nil)  // the accuracy itself is still the platform's
        let none = try PGNImporter.snapshot(game: games[2], username: "DrNykterstein", platform: .lichess)
        #expect(none.analysis == nil && none.platformAccuracy == nil)
    }

    @Test func chessComAccuraciesComeWithReviewedGames() async throws {
        let http = FixtureHTTP()
        let cc = "https://api.chess.com/pub/player/hikaru"
        http.route(cc + "/games/archives", file: "chesscom-archives.json")
        http.route(cc + "/games/2026/11", file: "chesscom-games-2026-11.json")
        http.route(cc + "/games/2026/10", file: "chesscom-games-2026-10.json")
        let games = try await ChessComClient(http: http).recentGames("hikaru", limit: 3)
        #expect(games.count == 3)
        #expect(games.allSatisfy { $0.accuracy?.source == "chesscom" && $0.evals == nil })
        // The newest game (November's last) was reviewed: white 79.8, black 88.91.
        #expect(games[0].accuracy == PlatformAccuracy(white: 79.8, black: 88.91, source: "chesscom"))
    }
}

/// Records events from the queue's stream.
private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var _all: [AnalysisQueue.Event] = []
    var all: [AnalysisQueue.Event] { lock.withLock { _all } }
    func append(_ e: AnalysisQueue.Event) { lock.withLock { _all.append(e) } }
    var finished: [GameSnapshot] {
        all.compactMap { if case .finished(let g) = $0 { g } else { nil } }
    }
}

private func listen(_ queue: AnalysisQueue) -> (Events, Task<Void, Never>) {
    let events = Events()
    let task = Task { for await e in queue.events { events.append(e) } }
    return (events, task)
}

private func eventually(_ timeout: Duration = .seconds(5), _ condition: () async -> Bool) async -> Bool {
    let end = ContinuousClock.now + timeout
    while ContinuousClock.now < end {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}

/// Throws `EngineYielded` on chosen background calls, like an engine preempted by a foreground request.
private final class YieldingEngine: ChessEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var _requests: [AnalysisRequest] = []
    let yieldOn: Set<Int>
    init(yieldOn: Set<Int>) { self.yieldOn = yieldOn }
    var requests: [AnalysisRequest] { lock.withLock { _requests } }

    func analyze(_ request: AnalysisRequest) async throws -> AnalysisResult {
        AnalysisResult(bestMove: "", lines: [PVLine(multipv: 1, depth: 5, score: Score(cp: 0), pv: [])])
    }
    func opponentMove(startFen: String, moves: [String], elo: Int) async throws -> String { "" }
    func analyzeInBackground(_ request: AnalysisRequest) async throws -> AnalysisResult {
        let n = lock.withLock { () -> Int in calls += 1; _requests.append(request); return calls }
        if yieldOn.contains(n) { throw EngineYielded() }
        return try await analyze(request)
    }
}

@Suite struct AnalysisQueueTests {
    @Test func quickJobsRunFirstAndAreMarkedQuickThenFullFollows() async throws {
        let engine = FakeEngine()
        let queue = AnalysisQueue(engine: engine, quick: .quick(nodes: 500, maxPly: 120), full: .full(depth: 14), idleDelay: .zero)
        let (events, listener) = listen(queue)
        defer { listener.cancel() }
        let a = game(["e2e4", "e7e5", "h2h4"]), b = game(["d2d4", "h7h5"])
        let hold = await queue.hold()
        await queue.enqueue([a], pass: .full)
        await queue.enqueue([b], pass: .quick)
        await queue.release(hold)
        #expect(await eventually { events.finished.count == 2 })
        let done = events.finished
        // The quick job jumped ahead of the full one queued before it.
        #expect(done[0].id == b.id && done[0].analysis?.pass == .quick && done[0].analysis?.nodes == 500)
        #expect(done[1].id == a.id && done[1].analysis?.pass == .full && done[1].analysis?.depth == 14)
        let quickRequests = engine.requests.filter { $0.nodes != nil }
        let fullRequests = engine.requests.filter { $0.nodes == nil }
        #expect(quickRequests.allSatisfy { $0.nodes == 500 && $0.multiPV == 1 })
        #expect(fullRequests.count == 4 && fullRequests.allSatisfy { $0.depth == 14 && $0.multiPV == 2 })
        #expect(await eventually { events.all.last == .drained })
    }

    @Test func alreadyAnalysedGamesAreSkipped() async throws {
        let engine = FakeEngine()
        let queue = AnalysisQueue(engine: engine, idleDelay: .zero)
        var quickDone = game(["e2e4"])
        quickDone.analysis = GameAnalysis(depth: 0, verdicts: [], whiteWin: [50], accuracyWhite: 1, accuracyBlack: 1, pass: .quick)
        await queue.enqueue([quickDone], pass: .quick)
        #expect(await queue.isIdle)
        await queue.enqueue([quickDone, quickDone], pass: .full)  // quick isn't full: queued once
        #expect(await queue.pending(.full) <= 1)
    }

    @Test func holdStopsTheSearchInFlightAndPausesUntilReleased() async throws {
        let engine = FakeEngine()
        engine.analysisGate.close()
        let queue = AnalysisQueue(engine: engine, quick: .quick(nodes: 500, maxPly: 120), idleDelay: .zero)
        let (events, listener) = listen(queue)
        defer { listener.cancel() }
        let g = game(["e2e4", "e7e5", "h2h4"])
        await queue.enqueue([g], pass: .quick)
        #expect(await eventually { engine.analysisGate.waiterCount == 1 })
        let asked = engine.requests.count

        // A foreground user arrives: the in-flight search is cancelled at once.
        let hold = await queue.hold()
        #expect(await eventually { engine.analysisGate.waiterCount == 0 })
        try await Task.sleep(for: .milliseconds(100))
        #expect(engine.requests.count == asked)  // nothing new while held
        #expect(events.finished.isEmpty)

        // Released: the same position is asked again and the game finishes.
        engine.analysisGate.open()
        await queue.release(hold)
        #expect(await eventually { events.finished.count == 1 })
        let positions = engine.requests.map(\.moves.count)
        #expect(positions.filter { $0 == positions[asked - 1] }.count == 2)  // the interrupted one, retried
        #expect(events.finished[0].analysis?.verdicts.count == 3)
    }

    @Test func idleDelayKeepsTheQueueQuietAfterARelease() async throws {
        let engine = FakeEngine()
        let queue = AnalysisQueue(engine: engine, idleDelay: .milliseconds(300))
        let hold = await queue.hold()
        await queue.enqueue([game(["e2e4"])], pass: .quick)
        try await Task.sleep(for: .milliseconds(50))
        #expect(engine.requests.isEmpty)
        await queue.release(hold)
        try await Task.sleep(for: .milliseconds(100))
        #expect(engine.requests.isEmpty)  // still inside the idle delay
        #expect(await eventually { !engine.requests.isEmpty })
    }

    @Test func yieldedPositionsAreRetriedAndTheResultIsComplete() async throws {
        let engine = YieldingEngine(yieldOn: [1, 3])
        let queue = AnalysisQueue(engine: engine, quick: .quick(nodes: 500, maxPly: 120), idleDelay: .zero)
        let (events, listener) = listen(queue)
        defer { listener.cancel() }
        let g = game(["e2e4", "e7e5", "h2h4"])
        await queue.enqueue([g], pass: .quick)
        #expect(await eventually { events.finished.count == 1 })
        let plan = try AnalysisPlan(startFen: Rules.startFen, moves: g.moves, mode: .quick(nodes: 500, maxPly: 120))
        #expect(engine.requests.count == plan.positions.count + 2)
        #expect(events.finished[0].analysis?.verdicts.count == 3)
    }

    @Test func illegalGameFailsWithoutStoppingTheQueue() async throws {
        let queue = AnalysisQueue(engine: FakeEngine(), idleDelay: .zero)
        let (events, listener) = listen(queue)
        defer { listener.cancel() }
        let bad = game(["e2e4", "zz99"]), good = game(["d2d4"])
        await queue.enqueue([bad, good], pass: .quick)
        #expect(await eventually { events.finished.count == 1 })
        #expect(events.all.contains(.failed(id: bad.id, pass: .quick)))
        #expect(events.finished[0].id == good.id)
    }
}
