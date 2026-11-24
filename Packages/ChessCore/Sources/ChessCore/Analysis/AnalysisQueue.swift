import Foundation

/// The app's low-priority analysis lane: quick passes for freshly imported games first, then
/// (idle) full-depth passes. It asks the engine for one position at a time through
/// `analyzeInBackground`, so a foreground user (Play, Review, a hint) never waits for more
/// than one small search:
/// - `hold()` (a screen that needs the engine is open) cancels the search in flight and
///   pauses the queue until every hold is released and `idleDelay` has passed;
/// - an engine that preempts background searches throws `EngineYielded`; the position is
///   simply asked again.
/// Results arrive on `events` in order; nothing partial is ever reported as finished.
public actor AnalysisQueue {
    public enum Event: Sendable, Equatable {
        case started(id: UUID, pass: AnalysisPass, positions: Int)
        case progress(id: UUID, done: Int, total: Int)
        /// The game with its new analysis (`analysis.pass` says which pass).
        case finished(GameSnapshot)
        /// Illegal moves or repeated engine errors: the game stays as it was.
        case failed(id: UUID, pass: AnalysisPass)
        /// Nothing left to do.
        case drained
    }

    public struct Hold: Hashable, Sendable {
        let id = UUID()
    }

    private struct Job: Sendable {
        var game: GameSnapshot
        var pass: AnalysisPass
    }

    public nonisolated let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation

    private let engine: any ChessEngine
    private let quickMode: AnalysisPlan.Mode
    private let fullMode: AnalysisPlan.Mode
    /// Quiet time after the last hold is released before the queue touches the engine again.
    private let idleDelay: Duration

    private var jobs: [Job] = []
    private var holds: Set<Hold> = []
    private var lastRelease: ContinuousClock.Instant?
    private var inFlight: Task<AnalysisResult, any Error>?
    private var worker: Task<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var current: (id: UUID, pass: AnalysisPass)?

    public init(engine: any ChessEngine, quick: AnalysisPlan.Mode = AnalysisPlan.quick,
                full: AnalysisPlan.Mode = AnalysisPlan.full, idleDelay: Duration = .seconds(2)) {
        self.engine = engine
        self.quickMode = quick
        self.fullMode = full
        self.idleDelay = idleDelay
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    // MARK: Jobs

    /// Adds games for `pass`. Games already analysed at least that well are skipped; a game
    /// already waiting for the same pass is not added twice. Quick jobs run before full ones.
    public func enqueue(_ games: [GameSnapshot], pass: AnalysisPass) {
        for game in games {
            switch pass {
            case .quick where game.analysis != nil: continue
            case .full where game.analysis?.isFull == true: continue
            default: break
            }
            guard !jobs.contains(where: { $0.game.id == game.id && $0.pass == pass }) else { continue }
            jobs.append(Job(game: game, pass: pass))
        }
        startIfNeeded()
    }

    /// Drops every waiting job (the one in flight finishes its current position and stops).
    public func removeAll() {
        jobs.removeAll()
        inFlight?.cancel()
    }

    public func pending(_ pass: AnalysisPass) -> Int {
        jobs.filter { $0.pass == pass }.count
    }

    public var isIdle: Bool { jobs.isEmpty }

    // MARK: Foreground holds

    /// A foreground user needs the engine: stop the background search now and pause.
    public func hold() -> Hold {
        let hold = Hold()
        holds.insert(hold)
        inFlight?.cancel()
        return hold
    }

    public func release(_ hold: Hold) {
        guard holds.remove(hold) != nil else { return }
        if holds.isEmpty {
            lastRelease = .now
            let resumed = waiters
            waiters.removeAll()
            resumed.forEach { $0.resume() }
        }
    }

    public var isHeld: Bool { !holds.isEmpty }

    // MARK: Worker

    private func startIfNeeded() {
        guard worker == nil, !jobs.isEmpty else { return }
        worker = Task { await self.work() }
    }

    private func nextJob() -> Job? {
        jobs.first { $0.pass == .quick } ?? jobs.first
    }

    private func remove(_ job: Job) {
        jobs.removeAll { $0.game.id == job.game.id && $0.pass == job.pass }
    }

    private func work() async {
        while true {
            // Pick the job only once the engine is free: a quick job queued meanwhile goes first.
            await waitUntilFree()
            guard let job = nextJob() else { break }
            let mode = job.pass == .quick ? quickMode : fullMode
            guard let plan = try? AnalysisPlan(startFen: job.game.startFen, moves: job.game.moves, mode: mode) else {
                remove(job)
                continuation.yield(.failed(id: job.game.id, pass: job.pass))
                continue
            }
            current = (job.game.id, job.pass)
            continuation.yield(.started(id: job.game.id, pass: job.pass, positions: plan.positions.count))
            var results: [Int: AnalysisResult] = [:]
            var index = 0
            var errors = 0
            var abandoned = false
            while index < plan.positions.count {
                await waitUntilFree()
                // The job may have been dropped (removeAll) while waiting.
                guard jobs.contains(where: { $0.game.id == job.game.id && $0.pass == job.pass }) else {
                    abandoned = true
                    break
                }
                let position = plan.positions[index]
                let request = plan.request(for: position)
                let engine = engine
                let task = Task { try await engine.analyzeInBackground(request) }
                inFlight = task
                do {
                    results[position] = try await task.value
                    index += 1
                    continuation.yield(.progress(id: job.game.id, done: index, total: plan.positions.count))
                } catch is EngineYielded {
                    // A foreground request took the engine; ask again once it is free.
                } catch is CancellationError {
                    // Cancelled by a hold (or removeAll): retry after the pause.
                } catch {
                    errors += 1
                    if errors >= 3 { break }
                }
                inFlight = nil
            }
            current = nil
            guard !abandoned else { continue }
            remove(job)
            if index == plan.positions.count {
                var game = job.game
                game.analysis = plan.assemble(results)
                continuation.yield(.finished(game))
            } else {
                continuation.yield(.failed(id: job.game.id, pass: job.pass))
            }
        }
        worker = nil
        continuation.yield(.drained)
    }

    /// Returns when no hold is active and the idle delay since the last release has passed.
    private func waitUntilFree() async {
        while true {
            if !holds.isEmpty {
                await withCheckedContinuation { waiters.append($0) }
                continue
            }
            if let last = lastRelease, ContinuousClock.now < last + idleDelay {
                try? await Task.sleep(until: last + idleDelay, clock: .continuous)
                continue
            }
            return
        }
    }
}
