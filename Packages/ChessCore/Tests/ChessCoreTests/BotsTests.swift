import Testing
@testable import ChessCore

@Test func botsHaveNoTrademarkName() {
    #expect(!Bot.all.contains { $0.name.localizedCaseInsensitiveContains("stockfish") })
    #expect(Bot.all.map(\.elo) == [600, 800, 1000, 1300, 1600, 1900, 2100, 2300])
}

@Test func botPersonasAreOrderedAndNamed() {
    #expect(Bot.all.map(\.id) == ["pip", "ron", "cadet", "blaze", "wall", "maestro", "vera", "apex"])
    #expect(Bot.all.last?.name == "Apex")
    #expect(Bot.all.last?.blurb == "Full strength. Good luck.")
    #expect(Bot.all.first?.avatarAsset == "Bots/pip")
}

@Test func playerProfileDefaultRating() {
    #expect(PlayerProfile.defaultRating == 800)
}
