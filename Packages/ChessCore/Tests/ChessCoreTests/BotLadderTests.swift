import Testing
@testable import ChessCore

@Test func newPlayerHasThreeOpenBotsAndPipNext() {
    let ladder = BotLadder(wins: [:])
    #expect(ladder.rungs[0] == .next)
    #expect(ladder.rungs[1] == .open)
    #expect(ladder.rungs[2] == .open)
    #expect(ladder.rungs[3] == .locked(requires: Bot.all[2]))
    #expect(ladder.rungs[7] == .locked(requires: Bot.all[6]))
    #expect(ladder.next?.id == "pip")
    #expect(ladder.isOpen(Bot.all[2]))
    #expect(!ladder.isOpen(Bot.all[3]))
}

@Test func beatingCadetOpensBlaze() {
    let ladder = BotLadder(wins: ["pip": 2, "ron": 1, "cadet": 1])
    #expect(ladder.rungs[0] == .beaten(wins: 2))
    #expect(ladder.rungs[3] == .next)
    #expect(ladder.rungs[4] == .locked(requires: Bot.all[3]))
    #expect(ladder.next?.id == "blaze")
}

@Test func skippedBotsStayOpenAndNextIsFirstUnbeaten() {
    let ladder = BotLadder(wins: ["cadet": 1])
    #expect(ladder.rungs[0] == .next)
    #expect(ladder.rungs[3] == .open)  // Cadet beaten opens Blaze
    #expect(ladder.rungs[4] == .locked(requires: Bot.all[3]))
}

@Test func ratingInReachOpensStrongerBots() {
    let ladder = BotLadder(wins: [:], rating: 1550)
    #expect(ladder.isOpen(Bot.all[4]))  // The Wall 1600
    #expect(!ladder.isOpen(Bot.all[5]))  // Maestro 1900
}

@Test func allBeatenNextIsStrongest() {
    let wins = Dictionary(uniqueKeysWithValues: Bot.all.map { ($0.id, 1) })
    #expect(BotLadder(wins: wins).next?.id == "apex")
}
