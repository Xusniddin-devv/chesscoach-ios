import Foundation
import Testing
@testable import ChessCore

/// Lichess 0S92h (mate in 3): White's Re6 is the setup; Black mates with Rc1+, Rxe1+, Rxf1#.
private let mateIn3 = Puzzle(
    id: "0S92h", fen: "2r3k1/p3n1p1/1p2q2p/3p1p2/5P2/P4Q2/6PP/4R2K w - - 0 43",
    moves: ["e1e6", "c8c1", "e6e1", "c1e1", "f3f1", "e1f1"], rating: 447, themes: ["mateIn3"])

/// Black's Kh8 sets up a back-rank mate; Re8# and Ra8# both mate.
private let twoMates = Puzzle(
    id: "two-mates", fen: "6k1/5ppp/8/8/8/8/5PPP/R3R1K1 b - - 0 1",
    moves: ["g8h8", "e1e8"], rating: 600, themes: ["mateIn1"])

@Test func puzzleSolverPlaysSetupThenAlternates() {
    var s = PuzzleSolver(puzzle: mateIn3)
    #expect(s.status == .setup)
    #expect(s.solverColor == .black)
    #expect(mateIn3.solverMoveCount == 3)
    do { let r = s.playSetup(); #expect(r == "e1e6") }
    #expect(s.status == .solving)
    do { let r = s.submit("c8c1"); #expect(r == .correct(reply: "e6e1")) }
    do { let r = s.playReply(); #expect(r == "e6e1") }
    do { let r = s.submit("c1e1"); #expect(r == .correct(reply: "f3f1")) }
    s.playReply()
    do { let r = s.submit("e1f1"); #expect(r == .solved) }
    #expect(s.solvedClean)
    #expect(s.played == mateIn3.moves)
}

@Test func puzzleSolverFailsOnWrongMoveAndRetries() {
    var s = PuzzleSolver(puzzle: mateIn3)
    s.playSetup()
    do { let r = s.submit("c8c2"); #expect(r == .wrong) }
    #expect(s.status == .failed)
    #expect(s.wrongMove == "c8c2")
    #expect(s.expectedMove == "c8c1")
    s.retry()
    #expect(s.status == .solving)
    #expect(s.fen == mateIn3.solvingFen)
    #expect(s.failures == 1)
    _ = s.submit("c8c1"); s.playReply()
    _ = s.submit("c1e1"); s.playReply()
    do { let r = s.submit("e1f1"); #expect(r == .solved) }
    #expect(!s.solvedClean)
}

@Test func puzzleSolverRejectsIllegalAndOutOfTurnMoves() {
    var s = PuzzleSolver(puzzle: mateIn3)
    #expect(s.submit("c8c1") == .illegal) // setup not played yet
    s.playSetup()
    do { let r = s.submit("c8c9"); #expect(r == .illegal) }
    #expect(s.submit("e6e1") == .illegal) // White's piece
    #expect(s.status == .solving)
}

@Test func puzzleSolverAcceptsAnyMateWhenTheExpectedMoveMates() {
    var s = PuzzleSolver(puzzle: twoMates)
    s.playSetup()
    do { let r = s.submit("a1a8"); #expect(r == .solved) }
    #expect(s.solvedClean)
}

@Test func puzzleSolverHintShowsFromSquareAndCostsTheCleanSolve() {
    var s = PuzzleSolver(puzzle: twoMates)
    s.playSetup()
    #expect(s.hintSquare == nil)
    s.showHint()
    #expect(s.hintSquare == Square("e1"))
    do { let r = s.submit("e1e8"); #expect(r == .solved) }
    #expect(!s.solvedClean)
}

@Test func puzzleWithoutSetupStartsSolving() {
    let p = Puzzle(id: "x", fen: "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", moves: ["a1a8"], rating: 500,
                   themes: [], hasSetupMove: false)
    var s = PuzzleSolver(puzzle: p)
    #expect(s.status == .solving)
    #expect(s.solverColor == .white)
    do { let r = s.submit("a1a8"); #expect(r == .solved) }
}

// MARK: Bank

@Test func bankLoadsSixThousandPuzzlesAcrossBands() {
    let all = PuzzleBank.all
    #expect(all.count == 6000)
    #expect(Set(all.map(\.id)).count == all.count)
    for lower in stride(from: 400, to: 2400, by: 100) {
        #expect(all.filter { (lower..<lower + 100).contains($0.rating) }.count == 300)
    }
    for theme in PuzzleBank.practiceThemes {
        #expect(all.filter { $0.themes.contains(theme) }.count >= 100, "\(theme)")
    }
}

@Test func bankPuzzlesAreLegalLines() {
    // Every puzzle replays fully and ends on the solver's move.
    for p in PuzzleBank.all {
        #expect(p.moves.count >= 2, "\(p.id)")
        #expect(p.moves.count % 2 == 0, "\(p.id) ends on the solver's move")
        #expect(Rules.fen(startFen: p.fen, moves: p.moves) != nil, "\(p.id)")
    }
}

@Test func bankFiltersByBandThemeAndExclusion() {
    let band = PuzzleBank.band(around: 800)
    #expect(band == 700..<900)
    let forks = PuzzleBank.puzzles(band: band, theme: "fork")
    #expect(!forks.isEmpty)
    #expect(forks.allSatisfy { band.contains($0.rating) && $0.themes.contains("fork") })
    let first = forks[0].id
    #expect(!PuzzleBank.puzzles(band: band, theme: "fork", excluding: [first]).contains { $0.id == first })
    #expect(PuzzleBank.band(around: 300) == 400..<600)
    #expect(PuzzleBank.band(around: 2400) == 2200..<2400)
}

@Test func dailyHashMatchesWebAndIsDeterministic() {
    #expect(PuzzleBank.hashString("2026-06-11") == 1_161_814_716)
    #expect(PuzzleBank.hashString("2026-11-24") == 1_162_589_316)
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let d1 = utc.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 1))!
    let d2 = utc.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 23))!
    let d3 = utc.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 1))!
    #expect(PuzzleBank.dayKey(d1, calendar: utc) == "2026-11-24")
    let a = PuzzleBank.daily(for: d1, calendar: utc)
    #expect(a != nil)
    #expect(a == PuzzleBank.daily(for: d2, calendar: utc))
    #expect(a != PuzzleBank.daily(for: d3, calendar: utc))
    #expect(PuzzleBank.dailyBand.contains(a!.rating))
}

@Test func weaknessMapsMotifsToThemes() {
    #expect(PuzzleBank.themes(for: .hangingPiece) == ["hangingPiece"])
    #expect(PuzzleBank.themes(for: .allowedFork) == ["fork"])
    #expect(PuzzleBank.themes(for: .missedMate) == ["mateIn1", "mateIn2"])
    #expect(PuzzleBank.themes(for: .missedCapture) == ["hangingPiece", "capturingDefender"])
    #expect(PuzzleBank.themes(for: .openingPrinciple) == ["opening"])
    let forks = PuzzleBank.forWeakness(.allowedFork, rating: 800)
    #expect(!forks.isEmpty)
    #expect(forks.allSatisfy { $0.themes.contains("fork") && abs($0.rating - 800) <= 300 })
}
