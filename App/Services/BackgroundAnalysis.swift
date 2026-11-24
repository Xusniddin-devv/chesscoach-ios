import SwiftUI
import SwiftData
import Observation
import ChessCore
import StockfishKit

/// The app's low-priority analysis: onboarding hands it the imported games it hasn't read,
/// it quick-analyses them (one engine request per position) while the user sets a goal, then
/// full-depth analyses imported games when the app is idle. Results go straight into the
/// stored `GameRecord`s; when the last quick result lands, the week's plan is rebuilt from
/// every imported game (Home's "Today's plan" follows through its query).
///
/// Foreground engine users never wait for it: screens that use the engine hold it
/// (`.holdsEngine()`), which stops the search in flight, and the engine itself preempts
/// background searches for any foreground request (`StockfishEngine.analyzeInBackground`).
@MainActor
@Observable
final class BackgroundAnalysis {
    /// Games waiting for (or in) a quick pass.
    var pendingQuick: Int { quickIDs.count }
    private var quickIDs: Set<UUID> = []
    /// The game being read right now and its progress.
    private(set) var current: UUID?
    private(set) var currentProgress: (done: Int, total: Int) = (0, 0)
    /// Positions searched since launch (the onboarding counter reads it).
    private(set) var positionsRead = 0

    @ObservationIgnored let queue: AnalysisQueue
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var listeners: [UUID: (AnalysisQueue.Event) -> Void] = [:]
    @ObservationIgnored private var pump: Task<Void, Never>?
    /// Set by onboarding when it saved games that were still being read: rebuild the plan
    /// once the quick pass is done.
    @ObservationIgnored private var replanAfterQuick = false
    /// Quick-analysed this session and still due for a full pass when the queue is idle.
    @ObservationIgnored private var fullPassDue = false

    init(engine: any ChessEngine = StockfishEngine.shared, idleDelay: Duration = .seconds(3)) {
        queue = AnalysisQueue(engine: engine, idleDelay: idleDelay)
        pump = Task { [weak self, queue] in
            for await event in queue.events {
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    /// Persist results through this context (the app's main context).
    func attach(_ context: ModelContext) {
        self.context = context
    }

    // MARK: Listening (onboarding)

    @discardableResult
    func listen(_ handler: @escaping (AnalysisQueue.Event) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = handler
        return id
    }

    func stopListening(_ id: UUID) { listeners[id] = nil }

    // MARK: Jobs

    func quick(_ games: [GameSnapshot]) {
        let todo = games.filter { $0.analysis == nil && !quickIDs.contains($0.id) }
        guard !todo.isEmpty else { return }
        quickIDs.formUnion(todo.map(\.id))
        Task { await queue.enqueue(todo, pass: .quick) }
    }

    /// Onboarding saved games that are still being read: replan when they are done.
    func replanWhenQuickDone() {
        if pendingQuick == 0 {
            refreshPlan()
            scheduleFullPass()
        } else {
            replanAfterQuick = true
        }
    }

    /// Launch: anything imported but unread gets a quick pass; quick results get a full pass.
    func resumeStoredWork() {
        guard let context else { return }
        let games = imported(in: context)
        quick(games)
        fullPassDue = games.contains { $0.needsFullAnalysis }
        if pendingQuick == 0 { scheduleFullPass() }
    }

    func stopAll() {
        quickIDs.removeAll()
        replanAfterQuick = false
        Task { await queue.removeAll() }
    }

    // MARK: Foreground holds

    func hold() async -> AnalysisQueue.Hold { await queue.hold() }
    func release(_ hold: AnalysisQueue.Hold) async { await queue.release(hold) }

    // MARK: Events

    private func handle(_ event: AnalysisQueue.Event) {
        switch event {
        case .started(let id, _, let positions):
            current = id
            currentProgress = (0, positions)
        case .progress(_, let done, let total):
            currentProgress = (done, total)
            positionsRead += 1
        case .finished(let game):
            current = nil
            if game.analysis?.pass == .quick {
                quickIDs.remove(game.id)
                fullPassDue = true
            }
            store(game)
        case .failed(let id, let pass):
            current = nil
            if pass == .quick { quickIDs.remove(id) }
        case .drained:
            current = nil
        }
        for listener in listeners.values { listener(event) }
        if pendingQuick == 0, case .finished(let g) = event, g.analysis?.pass == .quick { quickPassDone() }
        if pendingQuick == 0, case .failed(_, .quick) = event { quickPassDone() }
    }

    private func quickPassDone() {
        if replanAfterQuick {
            replanAfterQuick = false
            refreshPlan()
        }
        scheduleFullPass()
    }

    /// Full-depth passes for imported games, after the quick ones (the queue orders them and
    /// waits out its idle delay after any foreground use).
    private func scheduleFullPass() {
        guard fullPassDue, let context, UserDefaults.standard.bool(forKey: Pref.hasOnboarded) else { return }
        fullPassDue = false
        let games = imported(in: context).filter { $0.analysis != nil && $0.needsFullAnalysis }
        guard !games.isEmpty else { return }
        Task { await queue.enqueue(games, pass: .full) }
    }

    /// Writes a finished analysis into the stored game, if it is stored (onboarding saves at
    /// its end; until then it keeps results itself).
    private func store(_ game: GameSnapshot) {
        guard let context, let analysis = game.analysis else { return }
        let id = game.id
        guard let record = try? context.fetch(FetchDescriptor<GameRecord>(predicate: #Predicate { $0.id == id })).first,
              var stored = record.snapshot else { return }
        // Never replace a full analysis with a quick one.
        if stored.analysis?.isFull == true && !analysis.isFull { return }
        stored.analysis = analysis
        if let data = try? encodeSnapshot(stored) {
            record.snapshotData = data
            try? context.save()
        }
    }

    /// Rebuilds this week's plan from every imported game, keeping its start date so the day
    /// number doesn't move. No-op when the habits it is built on haven't changed.
    func refreshPlan() {
        guard let context, let plan = ProfileStore.plan(in: context),
              let profile = ProfileStore.profile(in: context) else { return }
        let games = imported(in: context)
        let report = WeaknessReport(games)
        guard report.gamesAnalysed > 0 else { return }
        let ownMistakes = games.flatMap(BlunderPuzzles.from(snapshot:)).count
        let lessons = Set(((try? context.fetch(FetchDescriptor<LessonProgress>())) ?? []).map(\.lessonId))
        let rebuilt = TrainingPlan.make(weaknesses: report.top, rating: profile.currentRating,
                                        ownMistakes: ownMistakes, completedLessons: lessons, now: plan.created)
        guard rebuilt != plan else { return }
        ProfileStore.savePlan(rebuilt, in: context)
    }

    private func imported(in context: ModelContext) -> [GameSnapshot] {
        ((try? context.fetch(FetchDescriptor<GameRecord>())) ?? []).compactMap(\.snapshot).filter(\.isImported)
    }
}

/// While this view is on screen the background queue leaves the engine alone.
private struct HoldsEngine: ViewModifier {
    @Environment(BackgroundAnalysis.self) private var analysis: BackgroundAnalysis?

    func body(content: Content) -> some View {
        content.task {
            guard let analysis else { return }
            let hold = await analysis.hold()
            // Sleeps until the view goes away (the task is cancelled then).
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
            await analysis.release(hold)
        }
    }
}

extension View {
    /// Pauses background analysis while this screen uses the engine (Play, lessons…).
    func holdsEngine() -> some View { modifier(HoldsEngine()) }
}
