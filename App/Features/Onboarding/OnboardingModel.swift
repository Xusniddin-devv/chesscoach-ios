import SwiftUI
import SwiftData
import Observation
import ChessCore
import StockfishKit

/// Drives onboarding: find the account (one username, looked up on chess.com and Lichess at
/// once) → import → reveal → goal → plan; or the new-player questions instead. Saves
/// everything at the end.
///
/// The import screen never makes the user wait for 20 full analyses: platform accuracies and
/// Lichess evals arrive with the games, the rest get a quick pass in `BackgroundAnalysis`, the
/// screen sweeps the 20 boards (real final positions and results) and moves on as soon as
/// enough is known for the plan. The remaining games keep being read through the goal and
/// plan steps, and after onboarding the plan is rebuilt when they are done.
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Hashable {
        case welcome, find, importing, question(Int), reveal, goal, plan

        /// The user has picked an account (or started the new-player questions): from here
        /// onboarding runs to its save, even if a profile synced from another device appears.
        var isEngaged: Bool {
            switch self {
            case .welcome, .find: false
            case .importing, .question, .reveal, .goal, .plan: true
            }
        }
    }

    enum Lookup: Equatable {
        case idle, checking, found(PlatformProfile), notFound, failed(String)
    }

    enum Phase: Equatable { case fetching, reading, done, failed(String) }

    /// One of the 20 boards on the import screen.
    struct Slot: Identifiable, Equatable {
        enum State: Equatable { case waiting, fetched, failed }
        let id: Int
        var state: State = .waiting
        var snapshot: GameSnapshot?
        /// Position after each ply (index 0 = start), for the big board's flip-through.
        var fens: [String] = []
        /// A real accuracy only: the platform's, else this app's analysis. Never estimated.
        var accuracy: Double?
        var analysed = false
        var won: Bool?

        var finalFen: String { fens.last ?? Rules.startFen }
    }

    static let gameLimit = 20
    /// Move on once this many games are analysed (or the budget runs out)…
    static let enoughGames = 8
    /// …measured from the moment the games are laid out. The sweep itself takes ~9 s.
    static let readBudget: Duration = .seconds(10.5)
    /// Time per board in the sweep.
    static let sweepStep: Duration = .milliseconds(450)
    /// The coach's "reading the rest" line stays this long before the reveal.
    static let handoffPause: Duration = .seconds(1.4)
    /// The coach asks how often the user plays once this many games are read or this long
    /// after the games are laid out, whichever comes first…
    static let askAfter = 3
    static let askAfterTime: Duration = .seconds(4)
    /// …and waits for the answer until this long after the games are laid out.
    static let questionCap: Duration = .seconds(12)

    let reimport: Bool
    var step: Step
    private(set) var history: [Step] = []

    // Find: one name, both platforms
    private(set) var platform: ImportPlatform?
    var username = ""
    private(set) var lookups: [ImportPlatform: Lookup] = [.chesscom: .idle, .lichess: .idle]
    private(set) var pickedProfile: PlatformProfile?

    /// The import screen knows enough to move on.
    private(set) var handoverReady = false
    /// Slot ids in the order their analysis arrived (the board shows the latest one).
    private(set) var finishOrder: [Int] = []
    /// The coach's one question during the import (shown once a few games are read).
    private(set) var askingFrequency = false
    /// The answer: it sizes the week's tasks.
    private(set) var frequency: PlayFrequency?

    // Import
    private(set) var phase: Phase = .fetching
    private(set) var slots: [Slot] = (0..<OnboardingModel.gameLimit).map { Slot(id: $0) }
    private(set) var fetchedCount = 0
    /// The board the sweep is on (nil before it starts and after it ends).
    private(set) var sweepIndex: Int?
    /// Ply shown on the big board while the sweep flips through the current game.
    private(set) var sweepPly = 0
    private(set) var sweepDone = false
    private(set) var gamesAnalysed = 0
    /// Plies whose evals came with the games (Lichess), counted as read.
    private(set) var platformPlies = 0
    private(set) var coachLine = CoachLine(.neutral, "")
    private(set) var games: [GameSnapshot] = []
    /// What the reveal shows: the weaknesses known when the import screen handed over.
    private(set) var report: WeaknessReport?

    // New player
    var answers: [Int?] = [nil, nil, nil]

    // Reveal, goal, plan
    private(set) var rating = PlayerProfile.defaultRating
    var target = 1000
    var months = 3
    private(set) var plan: TrainingPlan?
    /// `save(in:)` ran: the profile, goal, plan and games are stored.
    private(set) var saved = false

    /// The flow holds the screen against a profile synced from another device: the user has
    /// picked an account (or started the questions) and nothing is saved yet.
    var holdsOnboarding: Bool { step.isEngaged && !saved }

    @ObservationIgnored private var lookupTask: Task<Void, Never>?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var sweepTask: Task<Void, Never>?
    @ObservationIgnored private var listener: UUID?
    @ObservationIgnored private var positionsBase = 0
    @ObservationIgnored private var fastEngineOn = false
    @ObservationIgnored var makeClient: (ImportPlatform) -> any GameImportClient = { platform in
        switch platform {
        case .chesscom: ChessComClient()
        case .lichess: LichessClient()
        }
    }
    /// The app's background analysis (set by `OnboardingFlow`; tests pass their own).
    @ObservationIgnored var background: BackgroundAnalysis?
    /// More engine threads while onboarding reads games (nothing else uses the engine then);
    /// back to the app default when onboarding ends.
    @ObservationIgnored var setFastEngine: @Sendable (Bool) async -> Void = { fast in
        let threads = fast ? max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 2)) : EngineHub.defaultThreads
        await StockfishEngine.shared.configure(threads: threads, hashMB: EngineHub.defaultHashMB)
    }

    init(reimport: Bool = false) {
        self.reimport = reimport
        step = reimport ? .find : .welcome
    }

    // MARK: Navigation

    func go(_ next: Step) {
        history.append(step)
        // Leaving the find step: no slide. A focused text field being slid out could stay on
        // screen over the next step.
        if step == .find {
            var t = Transaction(animation: nil)
            t.disablesAnimations = true
            withTransaction(t) { step = next }
        } else {
            withAnimation(.snappy(duration: 0.35)) { step = next }
        }
        confirmStep()
    }

    /// Bumped one main-actor hop after every step change; the flow reads it. Measured on the
    /// simulator: a step change made while the import's state changes around it could be
    /// rendered with the old step (the view read it mid-update) and never refresh; the
    /// second change makes the flow read the step again.
    private(set) var stepRevision = 0

    private func confirmStep() {
        Task { @MainActor [weak self] in self?.stepRevision &+= 1 }
    }

    var canGoBack: Bool { !history.isEmpty && step != .importing }

    func back() {
        guard let previous = history.popLast() else { return }
        withAnimation(.snappy(duration: 0.35)) { step = previous }
        confirmStep()
    }

    // MARK: Find (one name, both platforms)

    /// Debounced lookup on both platforms at once as the user types.
    func usernameChanged() {
        lookupTask?.cancel()
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            withAnimation(.snappy(duration: 0.3)) { lookups = [.chesscom: .idle, .lichess: .idle] }
            return
        }
        lookups = [.chesscom: .checking, .lichess: .checking]
        let clients = ImportPlatform.allCases.map { ($0, makeClient($0)) }
        lookupTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await withTaskGroup(of: (ImportPlatform, Lookup).self) { group in
                for (platform, client) in clients {
                    group.addTask { (platform, await OnboardingModel.lookup(name, client: client)) }
                }
                for await (platform, result) in group {
                    guard !Task.isCancelled else { return }
                    withAnimation(.snappy(duration: 0.3)) { self?.lookups[platform] = result }
                }
            }
        }
    }

    /// Asks one platform again after a network or rate-limit failure.
    func retryLookup(_ platform: ImportPlatform) {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        lookups[platform] = .checking
        let client = makeClient(platform)
        Task { [weak self] in
            let result = await OnboardingModel.lookup(name, client: client)
            guard self?.username.trimmingCharacters(in: .whitespaces) == name else { return }
            withAnimation(.snappy(duration: 0.3)) { self?.lookups[platform] = result }
        }
    }

    nonisolated static func lookup(_ name: String, client: any GameImportClient) async -> Lookup {
        do {
            return .found(try await client.profile(name))
        } catch ImportError.userNotFound {
            return .notFound
        } catch is CancellationError {
            return .idle
        } catch ImportError.rateLimited {
            return .failed("\(client.platform.title) asked us to slow down.")
        } catch {
            return .failed("Couldn't reach \(client.platform.title).")
        }
    }

    func lookup(_ platform: ImportPlatform) -> Lookup { lookups[platform] ?? .idle }

    var foundProfiles: [PlatformProfile] {
        ImportPlatform.allCases.compactMap { if case .found(let p) = lookups[$0] { p } else { nil } }
    }

    var isSearching: Bool { lookups.values.contains(.checking) }

    /// The account the import reads.
    var foundProfile: PlatformProfile? { pickedProfile }

    /// The user chose their account: straight into the import.
    func pick(_ profile: PlatformProfile) {
        guard step == .find, !picking else { return }
        picking = true
        platform = profile.platform
        pickedProfile = profile
        // Let the find step drop keyboard focus before it goes: a focused field that is being
        // removed could keep the old step on screen over the import.
        releaseFocus?()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            self?.picking = false
            self?.startImport()
        }
    }

    /// Set by the find step: resigns its text field.
    @ObservationIgnored var releaseFocus: (() -> Void)?
    @ObservationIgnored private var picking = false

    // MARK: Import

    func startImport() {
        guard let platform, let profile = foundProfile else { return }
        if step != .importing { go(.importing) }
        resetImport()
        coachLine = CoachCommentary.fetching(platform: platform, count: Self.gameLimit)
        let client = makeClient(platform)
        let username = profile.username
        let setFastEngine = setFastEngine
        fastEngineOn = true

        importTask = Task { [weak self] in
            await setFastEngine(true)
            // 1. Fetch
            let fetched: [ImportedGame]
            do {
                let progress = AsyncStream<Int>.makeStream()
                async let games = client.recentGames(username, limit: Self.gameLimit) { progress.continuation.yield($0) }
                let watcher = Task { @MainActor [weak self] in
                    for await n in progress.stream { self?.markFetched(n) }
                }
                fetched = try await games
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
            let converted = await Task.detached(priority: .userInitiated) {
                fetched.compactMap { game -> (GameSnapshot, [String])? in
                    guard let s = try? PGNImporter.snapshot(game: game, username: username, platform: platform) else { return nil }
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
            self.layOut(converted)
            await self.read()
        }
    }

    private func resetImport() {
        importTask?.cancel()
        sweepTask?.cancel()
        phase = .fetching
        slots = (0..<Self.gameLimit).map { Slot(id: $0) }
        fetchedCount = 0
        sweepIndex = nil
        sweepPly = 0
        sweepDone = false
        gamesAnalysed = 0
        platformPlies = 0
        games = []
        report = nil
        handoverReady = false
        finishOrder = []
        askingFrequency = false
    }

    private func layOut(_ converted: [(GameSnapshot, [String])]) {
        games = converted.map(\.0)
        slots = (0..<Self.gameLimit).map { i in
            guard i < converted.count else { return Slot(id: i, state: .failed) }
            let s = converted[i].0
            return Slot(id: i, state: .fetched, snapshot: s, fens: converted[i].1,
                        accuracy: s.userAccuracy, analysed: s.analysis != nil, won: GameSummary(s).won)
        }
        fetchedCount = converted.count
        // Lichess games analysed there arrive graded already.
        let ready = games.filter { $0.analysis != nil }
        gamesAnalysed = ready.count
        finishOrder = slots.filter(\.analysed).map(\.id)
        platformPlies = ready.reduce(0) { $0 + ($1.analysis?.verdicts.count ?? 0) }
        phase = .reading
    }

    /// Sweeps the boards while the background queue reads; hands over once enough is known.
    private func read() async {
        let started = ContinuousClock.now
        if let background {
            positionsBase = background.positionsRead
            if let listener { background.stopListening(listener) }
            listener = background.listen { [weak self] event in self?.handle(event) }
            background.quick(games)
        }
        coachLine = CoachCommentary.analysing(index: 0, total: games.count, opponent: games.first?.opponentName)
        sweepTask = Task { [weak self] in await self?.sweep() }

        // Wait for the sweep and enough analysed games, or the budget.
        while !Task.isCancelled {
            if !askingFrequency, frequency == nil, ContinuousClock.now - started >= Self.askAfterTime { askFrequency() }
            let enough = gamesAnalysed >= min(Self.enoughGames, games.count)
            if sweepDone && (enough || ContinuousClock.now - started >= Self.readBudget) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !Task.isCancelled else { return }
        #if DEBUG
        OnboardingDebug.log("handover after \(ContinuousClock.now - started) analysed=\(gamesAnalysed)/\(games.count) positions=\(positionsRead)")
        #endif
        handOver()
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "onboardingHoldImport") { return }
        #endif
        // If the coach's question is open, give the user a moment to answer it (capped).
        while askingFrequency, frequency == nil, ContinuousClock.now - started < Self.questionCap, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: Self.handoffPause)
        guard !Task.isCancelled, step == .importing else { return }
        go(.reveal)
    }

    private func sweep() async {
        let frames = 9
        for i in slots.indices where slots[i].state == .fetched {
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.2)) { sweepIndex = i }
            // Flip through the game into its final position.
            let count = slots[i].fens.count
            for f in 1...frames {
                guard !Task.isCancelled else { return }
                sweepPly = (count - 1) * f / frames
                try? await Task.sleep(for: Self.sweepStep / frames)
            }
        }
        withAnimation(.snappy(duration: 0.3)) {
            sweepIndex = nil
            sweepDone = true
        }
    }

    private func handOver() {
        let report = WeaknessReport(games)
        self.report = report
        phase = .done
        handoverReady = true
        let remaining = games.count - gamesAnalysed
        coachLine = remaining > 0
            ? CoachLine(.thinking, "I've seen enough to start. Reading the rest while we set your goal.")
            : CoachCommentary.done(report: report)
        prepareReveal()
    }

    private func handle(_ event: AnalysisQueue.Event) {
        guard case .finished(let game) = event, let i = games.firstIndex(where: { $0.id == game.id }) else { return }
        let wasAnalysed = games[i].analysis != nil
        games[i] = game
        if let slot = slots.firstIndex(where: { $0.snapshot?.id == game.id }) {
            slots[slot].snapshot = game
            slots[slot].analysed = true
            withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
                slots[slot].accuracy = game.userAccuracy
                if !finishOrder.contains(slot) { finishOrder.append(slot) }
            }
        }
        if !wasAnalysed { gamesAnalysed += 1 }
        if step == .importing, phase == .reading {
            coachLine = CoachCommentary.afterGame(index: i, snapshot: game)
        }
        if gamesAnalysed >= Self.askAfter, frequency == nil, !askingFrequency, step == .importing { askFrequency() }
    }

    /// Positions read so far: this import's engine searches plus the evals that came with the games.
    var positionsRead: Int {
        platformPlies + max(0, (background?.positionsRead ?? 0) - positionsBase)
    }

    /// The game the sweep is on.
    var sweepSlot: Slot? { sweepIndex.map { slots[$0] } }

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

    private func askFrequency() {
        withAnimation(.snappy(duration: 0.35)) { askingFrequency = true }
        #if DEBUG
        OnboardingDebug.log("question shown")
        #endif
    }

    /// The coach's question, answered with a reply chip.
    func answerFrequency(_ f: PlayFrequency) {
        withAnimation(.snappy(duration: 0.3)) { frequency = f }
    }

    /// The worst move the user made in a slot's game, once analysed: the board's key moment.
    func keyMoment(_ slot: Slot) -> Verdict? {
        guard let s = slot.snapshot else { return nil }
        return GameSummary(s).worst
    }

    func cancelImport() {
        importTask?.cancel()
        sweepTask?.cancel()
        importTask = nil
        if let listener { background?.stopListening(listener) }
        listener = nil
        background?.stopAll()
        restoreEngine()
        // The abandoned account's games must not be saved later as the user's.
        resetImport()
        back()
    }

    func retryImport() {
        startImport()
    }

    private func restoreEngine() {
        guard fastEngineOn else { return }
        fastEngineOn = false
        let restore = setFastEngine
        Task.detached { await restore(false) }
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

    /// New to chess from the `find` step.
    func startQuestions() {
        resetImport()
        platform = nil
        pickedProfile = nil
        answers = [nil, nil, nil]
        go(.question(0))
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

    /// Built from everything read so far, including games finished after the reveal.
    func buildPlan(completedLessons: Set<String>) {
        let latest = games.isEmpty ? nil : WeaknessReport(games)
        let weaknesses = latest?.top ?? newPlayerAnswers?.weaknesses ?? []
        plan = TrainingPlan.make(weaknesses: weaknesses, rating: rating, ownMistakes: ownMistakePuzzles.count,
                                 completedLessons: completedLessons, preferredTrack: newPlayerAnswers?.track,
                                 frequency: frequency ?? .fewTimesAWeek)
    }

    /// Persists the profile, games, goal and plan, and marks onboarding done. Games still
    /// being read are saved as they are; the background queue fills them in and rebuilds the
    /// plan when the last one is done.
    func save(in context: ModelContext) {
        defer { saved = true }
        let profile = foundProfile
        ProfileStore.saveProfile(platform: platform, username: profile?.username ?? "",
                                 avatarURL: profile?.avatarURL, rating: rating, in: context)
        ProfileStore.saveGoal(rating: target, months: months, in: context)
        // Games only come from the account the user picked (a new player has none).
        if platform != nil, !games.isEmpty { ProfileStore.saveGames(games, in: context) }
        if let plan { ProfileStore.savePlan(plan, in: context) }
        let band = PuzzleBank.ratingRange
        let puzzleRating = min(max((rating / 100) * 100, band.lowerBound), band.upperBound - 100)
        UserDefaults.standard.set(puzzleRating, forKey: "puzzles.rating")
        if let frequency { UserDefaults.standard.set(frequency.rawValue, forKey: "onboarding.frequency") }
        UserDefaults.standard.set(true, forKey: Pref.hasOnboarded)
        if let listener { background?.stopListening(listener) }
        listener = nil
        if platform != nil, !games.isEmpty { background?.replanWhenQuickDone() }
        restoreEngine()
    }
}

