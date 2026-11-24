import Foundation
import Testing
@testable import ChessCore

private func games(_ count: Int, elo: Int, _ outcome: RatedGame.Outcome, accuracy: Double? = nil) -> [RatedGame] {
    Array(repeating: RatedGame(botElo: elo, outcome: outcome, accuracy: accuracy), count: count)
}

// MARK: Rating estimate (web rating.ts)

@Test func ratingNeedsThreeGames() {
    #expect(estimateRating([]) == nil)
    #expect(estimateRating(games(2, elo: 800, .win)) == nil)
    #expect(estimateRating(games(3, elo: 800, .win)) != nil)
}

@Test func ratingFromResultsOnly() {
    // perf = 600 + 400 * 0.5 * 0.9 = 780
    #expect(estimateRating(games(3, elo: 600, .win)) == 780)
    #expect(estimateRating(games(3, elo: 1000, .draw)) == 1000)
    // (780 + 780 + 420) / 3 = 660
    #expect(estimateRating(games(2, elo: 600, .win) + games(1, elo: 600, .loss)) == 660)
}

@Test func ratingBlendsAccuracy() {
    // perf 620, accRating 500 + 0 = 500 → 0.7·620 + 0.3·500 = 584 → 580
    #expect(estimateRating(games(3, elo: 800, .loss, accuracy: 60)) == 580)
    // perf 2480, accRating 500 + 40/35·1400 = 2100 → 1736 + 630 = 2366 → 2370
    #expect(estimateRating(games(3, elo: 2300, .win, accuracy: 100)) == 2370)
    // A game without accuracy uses its performance alone: (584 + 620 + 620) / 3 = 608 → 610
    let mixed = games(1, elo: 800, .loss, accuracy: 60) + games(2, elo: 800, .loss)
    #expect(estimateRating(mixed) == 610)
}

@Test func ratingClampsAndRoundsToTen() {
    #expect(estimateRating(games(3, elo: 3000, .win)) == 2400)
    // accRating clamps to 300 before blending: 0.7·120 + 0.3·300 = 174 → clamp 300
    #expect(estimateRating(games(3, elo: 300, .loss, accuracy: 0)) == 300)
    // perf 785 → rounds half up to 790
    #expect(estimateRating(games(3, elo: 605, .win)) == 790)
}

@Test func ratingUsesTheNewestFifteen() {
    // Newest first: 15 wins at 600 (780 each), then older losses that must be ignored.
    let newest = games(15, elo: 600, .win)
    #expect(estimateRating(newest + games(10, elo: 600, .loss)) == 780)
}

// MARK: Milestones

@Test func nextMilestoneIsTheFirstLevelAbove() {
    #expect(nextMilestone(300)! == (600, "Beginner I"))
    #expect(nextMilestone(780)! == (800, "Beginner II"))
    #expect(nextMilestone(800)! == (1000, "Novice I"))
    #expect(nextMilestone(1250)! == (1320, "Club I"))
    #expect(nextMilestone(2200)! == (2300, "Expert"))
    #expect(nextMilestone(2300) == nil)
    #expect(currentMilestone(500) == nil)
    #expect(currentMilestone(780)! == (600, "Beginner I"))
    #expect(currentMilestone(1250)! == (1200, "Novice II"))
    #expect(currentMilestone(2400)! == (2300, "Expert"))
}

// MARK: Weaknesses

@Test func weaknessesCountEachMotifAndSortByCount() {
    let d1 = Date(timeIntervalSince1970: 1_000)
    let d2 = Date(timeIntervalSince1970: 2_000)
    let d3 = Date(timeIntervalSince1970: 3_000)
    let result = aggregateWeaknesses([
        (motifs: [.hangingPiece], date: d1),
        (motifs: [.hangingPiece, .allowedFork], date: d3),
        (motifs: [.missedCapture], date: d2),
        (motifs: [.missedCapture], date: d1),
        (motifs: [.hangingPiece], date: d2),
        (motifs: [], date: d3),
    ])
    #expect(result.map(\.motif) == [.hangingPiece, .missedCapture, .allowedFork])
    #expect(result.map(\.count) == [3, 2, 1])
    #expect(result[0].lastSeen == d3)
    #expect(result[1].lastSeen == d2)
}

@Test func weaknessTiesGoToTheMostRecent() {
    let old = Date(timeIntervalSince1970: 1_000)
    let new = Date(timeIntervalSince1970: 2_000)
    let result = aggregateWeaknesses([(motifs: [.missedMate], date: old), (motifs: [.allowedMate], date: new)])
    #expect(result.map(\.motif) == [.allowedMate, .missedMate])
}

@Test func everyMotifHasBeginnerWording() {
    let all: [Motif] = [.allowedMate, .missedMate, .hangingPiece, .allowedFork, .missedCapture, .openingPrinciple]
    #expect(Motif.hangingPiece.title == "Leaving pieces undefended")
    for motif in all {
        #expect(!motif.title.isEmpty)
        #expect(motif.advice.hasSuffix("."))
        #expect(motif.headline.hasPrefix("You "))
    }
    #expect(Set(all.map(\.title)).count == all.count)
}

// MARK: Tiers

@Test func ratingTiersArePieces() {
    #expect(RatingTier(rating: 300) == .pawn)
    #expect(RatingTier(rating: 799) == .pawn)
    #expect(RatingTier(rating: 800) == .knight)
    #expect(RatingTier(rating: 1199) == .knight)
    #expect(RatingTier(rating: 1200) == .bishop)
    #expect(RatingTier(rating: 1500) == .rook)
    #expect(RatingTier(rating: 1800) == .queen)
    #expect(RatingTier(rating: 2099) == .queen)
    #expect(RatingTier(rating: 2100) == .king)
    #expect(RatingTier(rating: 2400) == .king)
    #expect(RatingTier(rating: 100) == .pawn)
    #expect(RatingTier.knight.next == .bishop)
    #expect(RatingTier.king.next == nil)
    #expect(RatingTier.knight.pieceKind == .knight)
}

@Test func tierProgressAndPointsToGo() {
    #expect(RatingTier.knight.pointsToNext(from: 940) == 260)
    #expect(RatingTier.knight.progress(of: 940) == 0.35)
    #expect(RatingTier.pawn.progress(of: 550) == 0.5)
    #expect(RatingTier.king.pointsToNext(from: 2200) == nil)
    #expect(RatingTier.king.progress(of: 2200) == 1)
}
