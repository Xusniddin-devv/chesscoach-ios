import Testing
@testable import ChessCore

@Test func levelMapping() {
    #expect(levelSettings(elo: 600) == LevelSettings(skillLevel: 0, depth: 4))
    #expect(levelSettings(elo: 1300) == LevelSettings(skillLevel: 8, depth: 9))
    #expect(levelSettings(elo: 2300) == LevelSettings(skillLevel: 20, depth: 15))
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
