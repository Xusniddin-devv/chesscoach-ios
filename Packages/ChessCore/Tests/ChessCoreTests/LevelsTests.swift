import Foundation
import Testing
@testable import ChessCore

@Test func botStylesAcrossTheLadder() {
    let t = BotTuning.builtIn
    #expect(botStyle(elo: 600, tuning: t) == .humanlike(HumanlikeStyle(depth: 8, multiPV: 12, temperatureCp: 250, blunderChance: 0.21)))
    if case .humanlike(let s) = botStyle(elo: 900, tuning: t) {  // halfway between 800 and 1000
        #expect(s.temperatureCp == 162.5 && abs(s.blunderChance - 0.11) < 1e-9)
    } else {
        Issue.record("900 should be humanlike")
    }
    #expect(botStyle(elo: 1600, tuning: t) == .limited(uciElo: 1400, movetimeMs: 800))
    #expect(botStyle(elo: 1500, tuning: t) == .limited(uciElo: 1320, movetimeMs: 800))
    #expect(botStyle(elo: 2300, tuning: t) == .limited(uciElo: 2100, movetimeMs: 800))
    #expect(botStyle(elo: 3000, tuning: t) == .full(depth: 15))  // lesson opponents
}

@Test func everyLadderBotIsWeakerThanTheOneAbove() {
    // Humanlike bots: a higher rating never raises temperature or blunder chance.
    var last = (temperature: Double.infinity, blunder: Double.infinity)
    for bot in Bot.all {
        switch botStyle(elo: bot.elo, tuning: .builtIn) {
        case .humanlike(let s):
            #expect(s.temperatureCp <= last.temperature && s.blunderChance <= last.blunder)
            last = (s.temperatureCp, s.blunderChance)
        case .limited(let elo, _):
            #expect(elo >= 1320 && elo <= 3190)
        case .full:
            Issue.record("\(bot.name) should not play at full strength")
        }
    }
}

@Test func tuningIsSanitized() {
    var t = BotTuning.builtIn
    t.humanlikeMultiPV = 500
    t.limitedMovetimeMs = 0
    t.anchors = [.init(elo: 1000, temperatureCp: .nan, blunderChance: 0.1)]
    let clean = t.sanitized()
    #expect(clean.humanlikeMultiPV == 20 && clean.limitedMovetimeMs == 100)
    #expect(clean.anchors == BotTuning.builtIn.anchors)
    let swapped = BotTuning(humanlikeBelow: 1500, uciEloOffset: 0, limitedMovetimeMs: 800, fullFrom: 2500,
                            fullDepth: 15, humanlikeDepth: 8, humanlikeMultiPV: 8,
                            anchors: [.init(elo: 1200, temperatureCp: 50, blunderChance: 0.9),
                                      .init(elo: 600, temperatureCp: 150, blunderChance: 0.1)]).sanitized()
    #expect(swapped.anchors.map(\.elo) == [600, 1200] && swapped.anchors[1].blunderChance == 0.5)
}

@Test func tuningDecodesFromJSON() throws {
    let data = try JSONEncoder().encode(BotTuning.builtIn)
    #expect(try JSONDecoder().decode(BotTuning.self, from: data) == .builtIn)
}

private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {  // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private let pickLines = [
    PVLine(multipv: 1, depth: 8, score: Score(cp: 50), pv: ["e2e4"]),
    PVLine(multipv: 2, depth: 8, score: Score(cp: 20), pv: ["d2d4"]),
    PVLine(multipv: 3, depth: 8, score: Score(cp: -400), pv: ["f2f3"]),
]
private let pickLegal = ["e2e4", "d2d4", "f2f3", "g2g4", "a2a3"]

private func pickCounts(_ style: HumanlikeStyle, runs: Int = 4000) -> [String: Int] {
    var rng = SeededRNG(state: 7)
    var counts: [String: Int] = [:]
    for _ in 0..<runs {
        counts[pickHumanlikeMove(lines: pickLines, legalMoves: pickLegal, style: style, using: &rng), default: 0] += 1
    }
    return counts
}

@Test func coldPickerPlaysTheBestLine() {
    let counts = pickCounts(HumanlikeStyle(depth: 8, multiPV: 8, temperatureCp: 1, blunderChance: 0))
    #expect(counts == ["e2e4": 4000])
}

@Test func warmPickerSpreadsOverCloseLinesAndRarelyHangs() {
    let counts = pickCounts(HumanlikeStyle(depth: 8, multiPV: 8, temperatureCp: 120, blunderChance: 0))
    // weights 1 : e^-0.25 (0.78) : e^-3.75 (0.02)
    #expect((2000...2500).contains(counts["e2e4", default: 0]))
    #expect((1500...2000).contains(counts["d2d4", default: 0]))
    #expect((20...150).contains(counts["f2f3", default: 0]))
    #expect(counts["g2g4"] == nil && counts["a2a3"] == nil)
}

@Test func blunderChancePlaysMovesOutsideTheLines() {
    let counts = pickCounts(HumanlikeStyle(depth: 8, multiPV: 8, temperatureCp: 1, blunderChance: 0.2))
    let random = counts["g2g4", default: 0] + counts["a2a3", default: 0]
    #expect((300...500).contains(random))  // 0.2 × 4000 × 2 of the 4 non-best moves
}

@Test func pickerFallsBackToALegalMove() {
    var rng = SeededRNG(state: 1)
    let style = HumanlikeStyle(depth: 8, multiPV: 8, temperatureCp: 50, blunderChance: 0)
    #expect(pickLegal.contains(pickHumanlikeMove(lines: [], legalMoves: pickLegal, style: style, using: &rng)))
    #expect(pickHumanlikeMove(lines: [], legalMoves: [], style: style, using: &rng) == "")
    let mateLines = [PVLine(multipv: 1, depth: 8, score: Score(mate: 1), pv: ["d1h5"]),
                     PVLine(multipv: 2, depth: 8, score: Score(cp: 300), pv: ["e2e4"])]
    let picks = (0..<200).map { _ in
        pickHumanlikeMove(lines: mateLines, legalMoves: ["d1h5", "e2e4"], style: style, using: &rng)
    }
    #expect(picks.allSatisfy { $0 == "d1h5" })
}

@Test func thinkTime() {
    #expect(thinkTimeMs(elo: 600, jitter: 0) == 315)
    #expect(thinkTimeMs(elo: 2300, jitter: 0.5) == 1700)
}

@Test func severityScalesWithLevel() {
    #expect(trainingSeverity(cpLoss: 130, level: 800) == .inaccuracy)
    #expect(trainingSeverity(cpLoss: 130, level: 1700) == .mistake)
    #expect(trainingSeverity(cpLoss: 460, level: 900) == .blunder)
}

@Test func severityBoundariesAndGood() {
    #expect(trainingSeverity(cpLoss: 0, level: 800) == .good)
    #expect(trainingSeverity(cpLoss: 119, level: 800) == .good)
    #expect(trainingSeverity(cpLoss: 120, level: 800) == .inaccuracy)
    #expect(trainingSeverity(cpLoss: 250, level: 800) == .mistake)
    #expect(trainingSeverity(cpLoss: 450, level: 800) == .blunder)
    #expect(trainingSeverity(cpLoss: 49, level: 2000) == .good)
    #expect(trainingSeverity(cpLoss: 50, level: 2000) == .inaccuracy)
    #expect(trainingSeverity(cpLoss: 250, level: 2000) == .blunder)
    #expect(TrainingSeverity.good < TrainingSeverity.blunder)
}
