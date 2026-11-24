import Testing
import SwiftData
import Foundation
import ChessCore
@testable import ChessCoach

@MainActor
struct TrainingStoreTests {
    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: PuzzleProgress.self, LessonProgress.self, StreakState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return ModelContext(container)
    }

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func cleanSolveSchedulesOneDayAndFailRetriesInTenMinutes() throws {
        let ctx = try context()
        TrainingStore.recordOutcome(puzzleId: "a", source: "bank", clean: true, solved: true, in: ctx, now: now)
        let a = try #require(TrainingStore.progress("a", in: ctx))
        #expect(a.reps == 1 && a.intervalDays == 1 && a.solvedCount == 1)
        #expect(a.due == now.addingTimeInterval(86_400))

        TrainingStore.recordOutcome(puzzleId: "b", source: "blunder", clean: false, solved: false, in: ctx, now: now)
        let b = try #require(TrainingStore.progress("b", in: ctx))
        #expect(b.lapses == 1 && b.failedCount == 1 && b.source == "blunder")
        #expect(b.due == now.addingTimeInterval(600))
        TrainingStore.recordLateSolve(puzzleId: "b", in: ctx, now: now)
        #expect(b.solvedCount == 1 && b.lapses == 1)
    }

    @Test func streakIsOneRowAndAdvancesByDay() throws {
        let ctx = try context()
        TrainingStore.recordActivity(in: ctx, now: now)
        TrainingStore.recordActivity(in: ctx, now: now.addingTimeInterval(3600))
        TrainingStore.recordActivity(in: ctx, now: now.addingTimeInterval(86_400))
        #expect(try ctx.fetch(FetchDescriptor<StreakState>()).count == 1)
        #expect(TrainingStore.streak(in: ctx).count == 2)
    }

    @Test func completingALessonTwiceKeepsOneRow() throws {
        let ctx = try context()
        TrainingStore.completeLesson("mate-back-rank", in: ctx)
        TrainingStore.completeLesson("mate-back-rank", in: ctx)
        #expect(try ctx.fetch(FetchDescriptor<LessonProgress>()).count == 1)
    }

    @Test func sessionRecordsSolveAndStreak() async throws {
        let ctx = try context()
        let puzzle = Puzzle(id: "m1", fen: "6k1/5ppp/8/8/8/8/5PPP/R3R1K1 b - - 0 1",
                            moves: ["g8h8", "e1e8"], rating: 600, themes: ["mateIn1"])
        let model = PuzzleSessionModel(setup: PuzzleSessionSetup(kind: .practice, title: "t", puzzles: [puzzle]))
        model.attach(ctx)
        model.start()
        try await Task.sleep(for: PuzzleSessionModel.setupDelay + .milliseconds(200))
        #expect(model.interactive)
        #expect(model.move("a1a8"))  // the other mate also counts
        #expect(model.solver.status == .solved)
        #expect(TrainingStore.progress("m1", in: ctx)?.solvedCount == 1)
        #expect(TrainingStore.streak(in: ctx).count == 1)
        model.next()
        #expect(model.finished)
    }

    @Test func freeUsersGetFivePuzzlesBesidesTheDaily() throws {
        let ctx = try context()
        for id in ["daily", "a", "b", "c"] {
            TrainingStore.recordOutcome(puzzleId: id, source: "bank", clean: true, solved: true, in: ctx, now: now)
        }
        TrainingStore.recordOutcome(puzzleId: "old", source: "bank", clean: true, solved: true, in: ctx,
                                    now: now.addingTimeInterval(-3 * 86_400))
        let rows = try ctx.fetch(FetchDescriptor<PuzzleProgress>())
        #expect(PuzzleAllowance.usedToday(rows, dailyId: "daily", now: now) == 3)
        #expect(PuzzleAllowance.remaining(rows, dailyId: "daily", isPro: false, now: now) == 2)
        #expect(PuzzleAllowance.remaining(rows, dailyId: "daily", isPro: true, now: now) == nil)
    }

    @Test func onlyTheFirstLessonOfATrackIsFree() {
        #expect(!LessonAllowance.isLocked(index: 0, isPro: false))
        #expect(LessonAllowance.isLocked(index: 1, isPro: false))
        #expect(!LessonAllowance.isLocked(index: 5, isPro: true))
    }
}
