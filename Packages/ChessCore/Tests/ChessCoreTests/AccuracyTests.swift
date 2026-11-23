import Testing
@testable import ChessCore

@Test func accuracyNoLoss() {
    let a = gameAccuracy(whiteWin: [50, 50], movers: [.white])
    #expect(a.white == 100.0 && a.black == 100)
}

@Test func accuracyTwentyPointDrop() {
    #expect(gameAccuracy(whiteWin: [60, 40], movers: [.white]).white == 40.0)
}
