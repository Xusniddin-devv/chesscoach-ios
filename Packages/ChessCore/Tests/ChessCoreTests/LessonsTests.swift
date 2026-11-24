import Foundation
import Testing
@testable import ChessCore

@Test func libraryHasAllThirtyFourLessons() {
    #expect(LessonLibrary.rowCount == 34)
    #expect(LessonLibrary.all.count == 34, "a lesson failed to resolve: an illegal move or FEN")
    #expect(LessonLibrary.lessons(in: .openings).count == 12)
    #expect(LessonLibrary.lessons(in: .endgames).count == 12)
    #expect(LessonLibrary.lessons(in: .checkmates).count == 10)
    #expect(Set(LessonLibrary.all.map(\.id)).count == 34)
}

@Test(arguments: LessonLibrary.all)
func lessonPositionIsLegal(_ lesson: Lesson) {
    // The side not to move must not be in check (the web once shipped four such positions).
    #expect(Position(fen: lesson.startFen) != nil, "\(lesson.id) FEN parses")
    #expect(!Rules.opponentInCheck(fen: lesson.startFen), "\(lesson.id) opponent already in check")
    #expect(!Rules.legalMoves(fen: lesson.startFen).isEmpty, "\(lesson.id) has legal moves")
    #expect(!lesson.summary.isEmpty)
}

@Test(arguments: LessonLibrary.all)
func lessonScriptIsLegalInSequence(_ lesson: Lesson) {
    var fen = lesson.startFen
    for step in lesson.steps {
        let applied = Rules.apply(uci: step.uci, to: fen)
        #expect(applied != nil, "\(lesson.id): \(step.san) legal in \(fen)")
        guard let applied else { return }
        #expect(!Rules.opponentInCheck(fen: applied.fenAfter))
        fen = applied.fenAfter
    }
    switch lesson.goal {
    case .line:
        #expect(lesson.steps.count >= 10, "\(lesson.id) is non-trivial")
        #expect(lesson.steps.contains { $0.side == .user })
        #expect(lesson.steps.filter { $0.side == .user }.allSatisfy { !$0.explanation.isEmpty })
    case .mate:
        #expect(lesson.steps.count == 1)
        #expect(lesson.userColor == .white)
        #expect(Rules.isCheckmate(fen: fen), "\(lesson.id) delivers mate")
    case .win, .draw:
        #expect(lesson.steps.isEmpty)
        let toMove: Piece.Color = lesson.startFen.contains(" b ") ? .black : .white
        #expect(toMove == lesson.userColor, "\(lesson.id) user to move")
    }
}

@Test func sanResolvesIncludingChecksAndCastling() {
    #expect(Rules.uci(san: "e4", fen: Rules.startFen) == "e2e4")
    #expect(Rules.uci(san: "Nf3", fen: Rules.startFen) == "g1f3")
    #expect(Rules.uci(san: "O-O", fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1") == "e1g1")
    #expect(Rules.uci(san: "Qe7", fen: Rules.startFen) == nil)
    let italian = LessonLibrary.lesson(id: "opening-italian")!
    #expect(italian.steps.last?.san == "Nc3")
    #expect(italian.steps[11].san == "Bb4+")
}

// MARK: Player

@Test func scriptedLineGuidesTheUserToTheEnd() {
    let lesson = LessonLibrary.lesson(id: "opening-italian")!
    var p = LessonPlayer(lesson: lesson)
    #expect(p.status == .userTurn)
    #expect(p.explanation == lesson.summary)
    do { let r = p.submit("d2d4"); #expect(r == .wrong) }
    #expect(p.hintLevel == 1)
    #expect(p.played.isEmpty)
    do { let r = p.submit("a2a3"); #expect(r == .wrong) }
    #expect(p.hintLevel == 2)
    do { let r = p.submit("e2e4"); #expect(r == .accepted) }
    #expect(p.hintLevel == 0)
    #expect(p.explanation == lesson.steps[0].explanation)
    #expect(p.status == .autoTurn)
    do { let r = p.playAuto(); #expect(r == "e7e5") }
    while p.status != .completed {
        if p.status == .autoTurn { p.playAuto() } else { let r = p.submit(p.expectedMove!); #expect(r == .accepted) }
    }
    #expect(p.played == lesson.steps.map(\.uci))
    #expect(p.userMovesDone == p.userMovesTotal)
}

@Test func blackRepertoireStartsWithTheAutoMove() {
    let lesson = LessonLibrary.lesson(id: "opening-caro-kann")!
    var p = LessonPlayer(lesson: lesson)
    #expect(p.status == .autoTurn)
    do { let r = p.playAuto(); #expect(r == "e2e4") }
    #expect(p.status == .userTurn)
    #expect(p.expectedMove == "c7c6")
}

@Test func mateLessonAcceptsTheMate() {
    var p = LessonPlayer(lesson: LessonLibrary.lesson(id: "mate-back-rank")!)
    do { let r = p.submit("a1a7"); #expect(r == .wrong) }
    do { let r = p.submit("a1a8"); #expect(r == .accepted) }
    #expect(p.status == .completed)
}

@Test func endgameFreePlayAsksForTheEngine() {
    var p = LessonPlayer(lesson: LessonLibrary.lesson(id: "endgame-kq-vs-k")!)
    #expect(p.status == .userTurn)
    do { let r = p.submit("c2c7"); #expect(r == .accepted) }
    #expect(p.status == .opponentTurn)
    do { let r = p.applyOpponent("e1e2"); #expect(!r) } // White king: not the engine move
    do { let r = p.applyOpponent("e8f8"); #expect(r) }
    #expect(p.status == .userTurn)
}

private func drill(_ goal: LessonGoal) -> Lesson {
    Lesson(id: "t", track: .endgames, title: "t", summary: "s", startFen: "4k3/8/8/8/8/8/3n4/4K3 w - - 0 1",
           userColor: .white, goal: goal, steps: [])
}

@Test func endgameDrawGoalCompletesOnDrawAndWinGoalFails() {
    var hold = LessonPlayer(lesson: drill(.draw))
    _ = hold.submit("e1d2") // K vs K
    #expect(hold.status == .completed)
    var win = LessonPlayer(lesson: drill(.win))
    _ = win.submit("e1d2")
    if case .failed = win.status {} else { Issue.record("expected failure, got \(win.status)") }
}

@Test func endgameWinGoalCompletesOnMate() {
    let lesson = Lesson(id: "t", track: .endgames, title: "t", summary: "s",
                        startFen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1", userColor: .white, goal: .win, steps: [])
    var p = LessonPlayer(lesson: lesson)
    _ = p.submit("a1a8")
    #expect(p.status == .completed)
}
