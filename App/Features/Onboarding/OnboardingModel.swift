import SwiftUI
import SwiftData
import Observation
import ChessCore
import StockfishKit

/// Drives onboarding: platform → username (live check) → import + analysis → reveal → goal
/// → plan; or the new-player questions instead of the import. Saves everything at the end.
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Hashable {
        case welcome, platform, username, importing, question(Int), reveal, goal, plan
    }

    enum Lookup: Equatable {
        case idle, checking, found(PlatformProfile), notFound, failed(String)
    }

    enum Phase: Equatable { case fetching, converting, analysing, done, failed(String) }

    /// One of the 20 tiles on the import screen.
    struct Slot: Identifiable, Equatable {
        enum State: Equatable { case waiting, fetched, analysing, done, failed }
        let id: Int
        var state: State = .waiting
        var snapshot: GameSnapshot?
        /// Position after each ply (index 0 = start), for the live board.
        var fens: [String] = []
        /// Ply shown while analysing.
        var ply = 0
        var accuracy: Double?
        var won: Bool?

        var fen: String {
            guard !fens.isEmpty else { return Rules.startFen }
            return fens[min(max(ply, 0), fens.count - 1)]
        }
    }

    static let gameLimit = 20

    let reimport: Bool
    var step: Step
    private(set) var history: [Step] = []

    // Platform + username
    var platform: ImportPlatform?
    var username = ""
    private(set) var lookup: Lookup = .idle

    // Import
    private(set) var phase: Phase = .fetching
    private(set) var slots: [Slot] = (0..<OnboardingModel.gameLimit).map { Slot(id: $0) }
    private(set) var fetchedCount = 0
    private(set) var movesAnalysed = 0
    private(set) var gamesDone = 0
    private(set) var coachLine = CoachLine(.neutral, "")
    private(set) var games: [GameSnapshot] = []
    private(set) var report: WeaknessReport?

    // New player
    var answers: [Int?] = [nil, nil, nil]

    // Reveal, goal, plan
    private(set) var rating = PlayerProfile.defaultRating
    var target = 1000
    var months = 3
    private(set) var plan: TrainingPlan?

    @ObservationIgnored private var lookupTask: Task<Void, Never>?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored var makeClient: (ImportPlatform) -> any GameImportClient = { platform in
        switch platform {
        case .chesscom: ChessComClient()
        case .lichess: LichessClient()
        }
    }
    @ObservationIgnored var engine: any ChessEngine = StockfishEngine.shared
    /// More engine threads while onboarding reads 20 games; back to the app default after.
    @ObservationIgnored var setFastEngine: @Sendable (Bool) async -> Void = { fast in
        let threads = fast ? max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 2)) : EngineHub.defaultThreads
        await StockfishEngine.shared.configure(threads: threads, hashMB: EngineHub.defaultHashMB)
    }

    init(reimport: Bool = false) {
        self.reimport = reimport
        step = reimport ? .platform : .welcome
    }

    // MARK: Navigation

    func go(_ next: Step) {
        history.append(step)
        withAnimation(.snappy(duration: 0.35)) { step = next }
    }

    var canGoBack: Bool { !history.isEmpty && step != .importing }

    func back() {
        guard let previous = history.popLast() else { return }
        withAnimation(.snappy(duration: 0.35)) { step = previous }
    }

    func choose(_ platform: ImportPlatform?) {
        self.platform = platform
        if platform == nil {
            answers = [nil, nil, nil]
            go(.question(0))
        } else {
            if case .found(let p) = lookup, p.platform != platform { lookup = .idle; username = "" }
            go(.username)
        }
    }

    // MARK: Username

    /// Debounced existence check as the user types.
    func usernameChanged() {
        lookupTask?.cancel()
        let name = username.trimmingCharacters(in: .whitespaces)
        guard let platform, !name.isEmpty else { lookup = .idle; return }
        lookup = .checking
        let client = makeClient(platform)
        lookupTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            do {
                let profile = try await client.profile(name)
                guard !Task.isCancelled else { return }
                self?.lookup = .found(profile)
            } catch ImportError.userNotFound {
                guard !Task.isCancelled else { return }
                self?.lookup = .notFound
            } catch is CancellationError {
            } catch ImportError.rateLimited {
                self?.lookup = .failed("\(platform.title) asked us to slow down. Try again in a minute.")
            } catch {
                guard !Task.isCancelled else { return }
                self?.lookup = .failed("Couldn't reach \(platform.title). Check your connection.")
            }
        }
    }

    var foundProfile: PlatformProfile? {
        if case .found(let p) = lookup { return p }
        return nil
    }

    // MARK: Import

    func startImport() {
        guard let platform, let profile = foundProfile else { return }
        go(.importing)
        importTask?.cancel()
        phase = .fetching
        slots = (0..<Self.gameLimit).map { Slot(id: $0) }
        fetchedCount = 0
        movesAnalysed = 0
        gamesDone = 0
        games = []
        report = nil
        coachLine = CoachCommentary.fetching(platform: platform, count: Self.gameLimit)
        let client = makeClient(platform)
        let engine = engine
        let username = profile.username

        importTask = Task { [weak self] in
            // 1. Fetch
            let pgns: [String]
            do {
                let progress = AsyncStream<Int>.makeStream()
                async let fetched = client.recentGames(username, limit: Self.gameLimit) { progress.continuation.yield($0) }
                let watcher = Task { @MainActor [weak self] in
                    for await n in progress.stream { self?.markFetched(n) }
                }
                pgns = try await fetched
                progress.continuation.finish()
                await watcher.value
            } catch is CancellationError {
                return
            } catch {
                self?.fail(error, platform: platform)
                return
            }
            guard let self, !Task.isCancelled else { return }

            // 2. Convert off the main actor (replaying every game once).
            self.phase = .converting
            let converted = await Task.detached(priority: .userInitiated) {
                pgns.compactMap { pgn -> (GameSnapshot, [String])? in
                    guard let s = try? PGNImporter.snapshot(pgn: pgn, username: username, platform: platform) else { return nil }
                    var fens = [s.startFen]
                    for uci in s.moves { if let next = Rules.apply(uci: uci, to: fens[fens.count - 1])?.fenAfter { fens.append(next) } }
                    return (s, fens)
                }
            }.value
            guard !Task.isCancelled else { return }
            if converted.isEmpty {
                self.phase = .failed("No standard games found on \(platform.title) for \(username).")
                self.coachLine = CoachLine(.concerned, "I couldn't find any standard games to read. Play a few and come back, or start fresh.")
                return
            }
            self.games = converted.map(\.0)
            self.slots = (0..<Self.gameLimit).map { i in
                guard i < converted.count else { return Slot(id: i, state: .failed) }
                return Slot(id: i, state: .fetched, snapshot: converted[i].0, fens: converted[i].1,
                            ply: converted[i].1.count - 1)
            }
            self.fetchedCount = converted.count

            // 3. Analyse, one game after another, events in order.
            self.phase = .analysing
            let events = AsyncStream<OnboardingEvent>.makeStream()
            let games = self.games
            let setFastEngine = self.setFastEngine
            var depth = OnboardingAnalysis.defaultDepth
            #if DEBUG
            // Screenshot hook: a shallower search so a scripted run takes seconds, not minutes.
            if UserDefaults.standard.integer(forKey: "onboardingDepth") > 0 { depth = UserDefaults.standard.integer(forKey: "onboardingDepth") }
            #endif
            let runner = Task.detached { [depth] in
                await setFastEngine(true)
                let out = await OnboardingAnalysis(engine: engine, depth: depth).run(games) { events.continuation.yield($0) }
                await setFastEngine(false)
                events.continuation.finish()
                return out
            }
            await withTaskCancellationHandler {
                for await event in events.stream { self.handle(event) }
            } onCancel: {
                runner.cancel()
            }
            let analysed = await runner.value
            guard !Task.isCancelled else { return }
            self.finishImport(analysed)
        }
    }

    private func markFetched(_ n: Int) {
        fetchedCount = n
        for i in 0..<min(n, slots.count) where slots[i].state == .waiting { slots[i].state = .fetched }
    }

    private func fail(_ error: Error, platform: ImportPlatform) {
        switch error {
        case ImportError.rateLimited: phase = .failed("\(platform.title) asked us to slow down. Try again in a minute.")
        case ImportError.userNotFound: phase = .failed("\(platform.title) has no games for this account.")
        default: phase = .failed("Couldn't reach \(platform.title). Check your connection and try again.")
        }
        coachLine = CoachLine(.concerned, "That didn't work. Let's try again in a moment.")
    }

    private func handle(_ event: OnboardingEvent) {
        switch event {
        case .gameStarted(let index, let total):
            guard index < slots.count else { return }
            slots[index].state = .analysing
            slots[index].ply = 0
            if index == 0 {
                coachLine = CoachCommentary.analysing(index: 0, total: total, opponent: slots[0].snapshot?.opponentName)
            }
        case .position(let index, let done, _):
            guard index < slots.count else { return }
            slots[index].ply = max(0, done - 1)
            movesAnalysed += 1
        case .gameFinished(let index, let snapshot):
            guard index < slots.count else { return }
            let summary = GameSummary(snapshot)
            slots[index].snapshot = snapshot
            slots[index].accuracy = summary.accuracy
            slots[index].won = summary.won
            slots[index].ply = slots[index].fens.count - 1
            withAnimation(.spring(duration: 0.6, bounce: 0.2)) { slots[index].state = .done }
            if index < games.count { games[index] = snapshot }
            gamesDone += 1
            coachLine = CoachCommentary.afterGame(index: index, snapshot: snapshot)
        case .gameFailed(let index):
            guard index < slots.count else { return }
            slots[index].state = .failed
        }
    }

    private func finishImport(_ analysed: [GameSnapshot]) {
        games = analysed
        let report = WeaknessReport(analysed)
        self.report = report
        phase = .done
        coachLine = CoachCommentary.done(report: report)
        prepareReveal()
    }

    /// The game being read now, if any.
    var liveSlot: Slot? { slots.first { $0.state == .analysing } }

    /// Stops the analysis and goes on with the games finished so far.
    func skipRest() {
        importTask?.cancel()
        importTask = nil
        let restore = setFastEngine
        Task.detached { await restore(false) }
        for i in slots.indices where slots[i].state == .analysing {
            slots[i].state = .fetched
            slots[i].ply = max(0, slots[i].fens.count - 1)
        }
        let report = WeaknessReport(games)
        self.report = report
        phase = .done
        prepareReveal()
        go(.reveal)
    }

    func cancelImport() {
        importTask?.cancel()
        importTask = nil
        let restore = setFastEngine
        Task.detached { await restore(false) }
        back()
    }

    func retryImport() {
        if history.last == .username { history.removeLast() } else { history.removeAll { $0 == .importing } }
        step = .username
        startImport()
    }

    // MARK: Reveal, goal, plan

    var answersComplete: Bool { answers.allSatisfy { $0 != nil } }

    var newPlayerAnswers: NewPlayerAnswers? {
        guard let r = answers[0].flatMap(NewPlayerAnswers.Rules.init(rawValue:)),
              let p = answers[1].flatMap(NewPlayerAnswers.Played.init(rawValue:)),
              let g = answers[2].flatMap(NewPlayerAnswers.Goal.init(rawValue:)) else { return nil }
        return NewPlayerAnswers(rules: r, played: p, goal: g)
    }

    func prepareReveal() {
        if let profile = foundProfile, let r = profile.currentRating {
            rating = r
        } else if let answers = newPlayerAnswers {
            rating = answers.estimatedRating
        } else {
            let ratings = games.map(\.playerRatingUsed)
            rating = ratings.isEmpty ? PlayerProfile.defaultRating : ratings.reduce(0, +) / ratings.count
        }
        #if DEBUG
        // Screenshot hook: show a beginner tier over real imported games.
        let forced = UserDefaults.standard.integer(forKey: "onboardingRating")
        if forced > 0 { rating = forced }
        #endif
        target = GoalModel.suggestedTarget(current: rating, months: months)
    }

    func answer(_ question: Int, _ value: Int) {
        answers[question] = value
        if question < 2 {
            go(.question(question + 1))
        } else {
            prepareReveal()
            go(.reveal)
        }
    }

    var distribution: RatingDistribution { .forPlatform(platform) }

    var chance: Int { GoalModel.chance(current: rating, target: target, months: months) }

    /// Puzzles from the user's own analysed mistakes.
    var ownMistakePuzzles: [Puzzle] { games.flatMap(BlunderPuzzles.from(snapshot:)) }

    func buildPlan(completedLessons: Set<String>) {
        let weaknesses = report?.top ?? newPlayerAnswers?.weaknesses ?? []
        plan = TrainingPlan.make(weaknesses: weaknesses, rating: rating, ownMistakes: ownMistakePuzzles.count,
                                 completedLessons: completedLessons, preferredTrack: newPlayerAnswers?.track)
    }

    /// Persists the profile, games, goal and plan, and marks onboarding done.
    func save(in context: ModelContext) {
        let profile = foundProfile
        ProfileStore.saveProfile(platform: platform, username: profile?.username ?? "",
                                 avatarURL: profile?.avatarURL, rating: rating, in: context)
        ProfileStore.saveGoal(rating: target, months: months, in: context)
        if !games.isEmpty { ProfileStore.saveGames(games, in: context) }
        if let plan { ProfileStore.savePlan(plan, in: context) }
        let band = PuzzleBank.ratingRange
        let puzzleRating = min(max((rating / 100) * 100, band.lowerBound), band.upperBound - 100)
        UserDefaults.standard.set(puzzleRating, forKey: "puzzles.rating")
        UserDefaults.standard.set(true, forKey: Pref.hasOnboarded)
    }
}
