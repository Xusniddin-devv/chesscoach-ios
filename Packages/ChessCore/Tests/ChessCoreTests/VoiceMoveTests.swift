import Testing
@testable import ChessCore

// Ported from the web's src/lib/voiceMove.test.ts, plus cases for the Swift changes.

@Test func voicePawnPushFromSquareAlone() {
    #expect(VoiceMove.parse("e4", fen: Rules.startFen) == "e2e4")
    #expect(VoiceMove.parse("E4.", fen: Rules.startFen) == "e2e4")
    #expect(VoiceMove.parse("e 4", fen: Rules.startFen) == "e2e4")
}

@Test func voiceKnightToC3() {
    #expect(VoiceMove.parse("knight to c3", fen: Rules.startFen) == "b1c3")
    #expect(VoiceMove.parse("Knight two C3", fen: Rules.startFen) == "b1c3")
}

@Test func voiceHomophonesAndNumberWords() {
    #expect(VoiceMove.parse("night f three", fen: Rules.startFen) == "g1f3")
    #expect(VoiceMove.parse("horse foxtrot 3", fen: Rules.startFen) == "g1f3")
    #expect(VoiceMove.parse("pawn see four", fen: Rules.startFen) == "c2c4")
    #expect(VoiceMove.parse("d for", fen: Rules.startFen) == "d2d4")
}

@Test func voiceCaptures() {
    let fen = "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"
    #expect(VoiceMove.parse("pawn takes d5", fen: fen) == "e4d5")
    #expect(VoiceMove.parse("e takes d5", fen: fen) == "e4d5")
}

@Test func voiceCastling() {
    let fen = "r3k2r/pppq1ppp/2npbn2/2b1p3/2B1P3/2NPBN2/PPPQ1PPP/R3K2R w KQkq - 0 1"
    #expect(VoiceMove.parse("castle kingside", fen: fen) == "e1g1")
    #expect(VoiceMove.parse("castles short", fen: fen) == "e1g1")
    #expect(VoiceMove.parse("castle queenside", fen: fen) == "e1c1")
    #expect(VoiceMove.parse("O-O-O", fen: fen) == "e1c1")
    #expect(VoiceMove.parse("castle", fen: fen) == "e1g1")
}

@Test func voiceSingleKnightReachingSquare() {
    #expect(VoiceMove.parse("knight to f5", fen: "4k3/8/8/8/3N4/8/8/3NK3 w - - 0 1") == "d4f5")
}

@Test func voiceAmbiguousNeedsAHint() {
    // Knights on b1 and f1 both reach d2.
    let fen = "4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1"
    #expect(VoiceMove.parse("knight d2", fen: fen) == nil)
    #expect(VoiceMove.parse("knight b to d2", fen: fen) == "b1d2")
    #expect(VoiceMove.parse("knight f1 to d2", fen: fen) == "f1d2")
}

@Test func voicePromotion() {
    let fen = "8/P6k/8/8/8/8/8/4K3 w - - 0 1"
    #expect(VoiceMove.parse("a8", fen: fen) == "a7a8q")
    #expect(VoiceMove.parse("a8 promote to knight", fen: fen) == "a7a8n")
}

@Test func voiceNothingRecognisable() {
    #expect(VoiceMove.parse("hello there", fen: Rules.startFen) == nil)
    #expect(VoiceMove.parse("", fen: Rules.startFen) == nil)
    #expect(VoiceMove.parse("e5", fen: Rules.startFen) == nil)  // not legal
}
