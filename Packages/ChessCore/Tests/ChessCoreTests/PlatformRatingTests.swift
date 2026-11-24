import Foundation
import Testing
@testable import ChessCore

// An imported player (chess.com "hikaru", rapid 2838) after onboarding, plus a few bot games.
// The platform rating is what the app shows; its own estimate is for players without one.

private let hikaruRapid = 2838

private func bot(_ id: String, _ outcome: RatedGame.Outcome, accuracy: Double? = nil) -> RatedGame {
    RatedGame(botElo: Bot.all.first { $0.id == id }!.elo, outcome: outcome, accuracy: accuracy)
}

/// Hikaru's imported games: ~3050-rated opponents, mostly won, chess.com accuracies.
private let hikaruImports = Array(repeating: RatedGame(botElo: 3050, outcome: .win, accuracy: 86), count: 18)
    + [RatedGame(botElo: 3060, outcome: .loss, accuracy: 75), RatedGame(botElo: 3064, outcome: .draw, accuracy: 87)]

@Test func theAppEstimateCannotStandForAStrongImport() {
    // The bug: the app's own estimate caps any performance at 2400 ...
    #expect(estimateRating(hikaruImports) == 2400)
    // ... and a bot game is worth at most the bot's Elo + 180, so the ladder's first bots
    // (Pip, Ron, Cadet) pull any player towards ~900-1000 once they fill the window.
    let ladder = [bot("pip", .win), bot("ron", .win), bot("cadet", .win)]
    #expect(estimateRating(Array(repeating: ladder, count: 5).flatMap { $0 })! < 1000)
}

@Test func importedPlayerRatingIsThePlatformRating() {
    let twoBotGames = [bot("pip", .win), bot("apex", .loss)]
    #expect(playerRating(platform: hikaruRapid, games: twoBotGames + hikaruImports) == 2838)
    #expect(playerRating(platform: hikaruRapid, games: []) == 2838)
    // Never clamped to the estimate's range.
    #expect(playerRating(platform: 3442, games: hikaruImports) == 3442)
}

@Test func newPlayerRatingIsStillTheAppEstimate() {
    let games = [bot("ron", .win), bot("ron", .win), bot("ron", .loss)]
    #expect(playerRating(platform: nil, games: games) == estimateRating(games))
    #expect(playerRating(platform: nil, games: Array(games.prefix(2))) == nil)
}

// MARK: Ladder for a strong player

@Test func strongPlayerIsNotSentToPip() {
    let ladder = BotLadder(wins: [:], rating: hikaruRapid)
    #expect(Bot.all.allSatisfy(ladder.isOpen))
    #expect(ladder.next?.id == "apex")
    #expect(ladder.rung(for: Bot.all[0]) == .open)
}

@Test func strongPlayerWhoBeatApexKeepsApexAsNext() {
    #expect(BotLadder(wins: ["apex": 1], rating: hikaruRapid).next?.id == "apex")
    #expect(BotLadder(wins: ["pip": 1], rating: hikaruRapid).next?.id == "apex")
}

@Test func ladderNextSkipsOnlyFarEasierBots() {
    #expect(BotLadder(wins: [:], rating: 1000).next?.id == "pip")
    #expect(BotLadder(wins: [:], rating: nil).next?.id == "pip")
    // 1550: Pip (600), Ron (800) and Cadet (1000) are far below; Blaze (1300) is the first useful one.
    #expect(BotLadder(wins: [:], rating: 1550).next?.id == "blaze")
    // 1800 who already beat everything up to The Wall: Maestro.
    #expect(BotLadder(wins: ["blaze": 1, "wall": 1], rating: 1800).next?.id == "maestro")
}

// MARK: Goal picker

@Test func goalWindowAlwaysHasRoomAboveTheRating() {
    for current in [300, 940, 1500, 2838, 2990, 3442] {
        let window = GoalModel.pickerWindow(current: current)
        #expect(window.upperBound - window.lowerBound == GoalModel.pickerSpan)
        #expect(window.contains(current))
        #expect(GoalModel.minimumTarget(current: current) > current)
        #expect(GoalModel.minimumTarget(current: current) <= window.upperBound)
        #expect(window.contains(GoalModel.suggestedTarget(current: current)))
        #expect(GoalModel.suggestedTarget(current: current) > current)
    }
    // Unchanged where it already worked.
    #expect(GoalModel.pickerWindow(current: 940) == 600...2100)
    #expect(GoalModel.pickerWindow(current: 2838) == 1500...3000)
}

@Test func clampedGoalStaysAboveTheRating() {
    // Dragging to the far left never sets a goal at or below today's rating.
    #expect(GoalModel.clampTarget(100, current: 3442) == 3450)
    #expect(GoalModel.clampTarget(5000, current: 3442) == GoalModel.pickerWindow(current: 3442).upperBound)
    #expect(GoalModel.clampTarget(1500, current: 2838) == 2850)
    #expect(GoalModel.clampTarget(1500, current: 960) == 1500)
}
