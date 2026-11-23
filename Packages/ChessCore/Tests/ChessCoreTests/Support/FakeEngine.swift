import Foundation
@testable import ChessCore

struct FakeEngineError: Error {}

struct OpponentCall: Equatable {
    var startFen: String
    var moves: [String]
    var elo: Int
}

/// A suspension point that test code opens and closes. Waiters either honour task
/// cancellation (throw `CancellationError`, like the real engine) or ignore it until opened.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var cancelled: Set<UUID> = []

    var waiterCount: Int { lock.withLock { waiters.count } }

    func close() { lock.withLock { closed = true } }

    func open() {
        let toResume = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            closed = false
            defer { waiters.removeAll() }
            return Array(waiters.values)
        }
        toResume.forEach { $0.resume() }
    }

    func pass(honoringCancellation: Bool) async throws {
        let id = UUID()
        if honoringCancellation {
            await withTaskCancellationHandler {
                await suspend(id)
            } onCancel: {
                let c = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                    if let c = waiters.removeValue(forKey: id) { return c }
                    cancelled.insert(id)
                    return nil
                }
                c?.resume()
            }
            try Task.checkCancellation()
        } else {
            await suspend(id)
        }
    }

    private func suspend(_ id: UUID) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock { () -> Bool in
                if !closed || cancelled.contains(id) { return true }
                waiters[id] = c
                return false
            }
            if resumeNow { c.resume() }
        }
    }
}

/// Scripted `ChessEngine` for session tests.
final class FakeEngine: ChessEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [String: AnalysisResult] = [:]
    private var _requests: [AnalysisRequest] = []
    private var _opponentCalls: [OpponentCall] = []
    private var botMoves: [String]
    private var throwOnNextOpponentMove = false
    private var throwOnNextAnalyze = false

    let defaultResult: AnalysisResult
    let analysisGate = Gate()
    let opponentGate = Gate()
    let honorsCancellation: Bool

    init(botMoves: [String] = [],
         defaultResult: AnalysisResult = AnalysisResult(
             bestMove: "", lines: [PVLine(multipv: 1, depth: 16, score: Score(cp: 0), pv: [])]),
         honorsCancellation: Bool = true) {
        self.botMoves = botMoves
        self.defaultResult = defaultResult
        self.honorsCancellation = honorsCancellation
    }

    var requests: [AnalysisRequest] { lock.withLock { _requests } }
    var opponentCalls: [OpponentCall] { lock.withLock { _opponentCalls } }

    func script(_ request: AnalysisRequest, _ result: AnalysisResult) {
        lock.withLock { results[request.cacheKey] = result }
    }

    func failNextOpponentMove() { lock.withLock { throwOnNextOpponentMove = true } }
    func failNextAnalyze() { lock.withLock { throwOnNextAnalyze = true } }

    func analyze(_ request: AnalysisRequest) async throws -> AnalysisResult {
        let shouldThrow = lock.withLock { () -> Bool in
            _requests.append(request)
            defer { throwOnNextAnalyze = false }
            return throwOnNextAnalyze
        }
        if shouldThrow { throw FakeEngineError() }
        try await analysisGate.pass(honoringCancellation: honorsCancellation)
        return lock.withLock { results[request.cacheKey] ?? defaultResult }
    }

    func opponentMove(startFen: String, moves: [String], elo: Int) async throws -> String {
        let shouldThrow = lock.withLock { () -> Bool in
            _opponentCalls.append(OpponentCall(startFen: startFen, moves: moves, elo: elo))
            defer { throwOnNextOpponentMove = false }
            return throwOnNextOpponentMove
        }
        try await opponentGate.pass(honoringCancellation: honorsCancellation)
        if shouldThrow { throw FakeEngineError() }
        return lock.withLock { botMoves.isEmpty ? "" : botMoves.removeFirst() }
    }
}
