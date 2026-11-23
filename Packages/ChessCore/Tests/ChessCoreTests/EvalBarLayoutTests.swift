import Testing
@testable import ChessCore

@Test func evalBarLightIsAlwaysWhite() {
    #expect(EvalBarLayout.whiteAnchoredAtBottom(orientation: .white))
    #expect(!EvalBarLayout.whiteAnchoredAtBottom(orientation: .black))
    #expect(abs(EvalBarLayout.whiteFraction(whiteCp: -500) - 0.137) < 0.001)
}
