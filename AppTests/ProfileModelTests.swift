import Testing
import SwiftData
import Foundation
import ChessCore
@testable import ChessCoach

@MainActor
struct ProfileModelTests {
    private let container: ModelContainer

    init() throws {
        container = try ModelContainer(
            for: GameRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func verdict(ply: Int, mover: Piece.Color, _ cls: MoveClass, motifs: [Motif] = []) -> Verdict {
        let even = AnalysisResult(bestMove: "d2d4", lines: [PVLine(multipv: 1, depth: 14, score: Score(cp: 0), pv: ["d2d4"])])
        var v = classifyPlayed(PlayedMoveInput(
            fenBefore: Rules.startFen, fenAfter: Rules.apply(uci: "e2e4", to: Rules.startFen)!.fenAfter,
            playedUci: "e2e4", playedSan: "e4", mover: .white, ply: 1, before: even, after: even))
        v.ply = ply
        v.mover = mover
        v.classification = cls
        v.motifs = motifs
        return v
    }

    @discardableResult
    private func save(bot: String = "ron", result: GameResult, user: Piece.Color = .white,
                      daysAgo: Double = 0, accuracy: Double? = nil, verdicts: [Verdict] = []) throws -> GameRecord {
        let analysis = accuracy.map {
            GameAnalysis(depth: 14, verdicts: verdicts, whiteWin: [], accuracyWhite: $0, accuracyBlack: 50)
        }
        let snapshot = GameSnapshot(
            id: UUID(), date: Date(timeIntervalSince1970: 1_800_000_000 - daysAgo * 86_400), botId: bot,
            userColor: user, mode: .training, startFen: Rules.startFen, moves: [], sans: [],
            result: result, verdicts: [], analysisVersion: 1, playerRatingUsed: 800, analysis: analysis)
        let record = try GameRecord(snapshot: snapshot)
        container.mainContext.insert(record)
        try container.mainContext.save()
        return record
    }

    private var model: ProfileModel {
        ProfileModel(records: (try? container.mainContext.fetch(FetchDescriptor<GameRecord>())) ?? [])
    }

    @Test func noGames() {
        let m = model
        #expect(m.games.isEmpty)
        #expect(m.estimate == nil)
        #expect(m.trainingRating == PlayerProfile.defaultRating)
        #expect(m.gamesUntilRating == 3)
        #expect(m.winRate == nil)
        #expect(m.recentAccuracy == nil)
        #expect(m.moveQuality.isEmpty)
        #expect(m.weaknesses.isEmpty)
        #expect(m.tier == .pawn)
    }

    @Test func oneAndTwoGamesHaveNoRatingYet() throws {
        try save(result: .whiteWins)
        #expect(model.estimate == nil)
        #expect(model.gamesUntilRating == 2)
        try save(result: .blackWins, daysAgo: 1)
        #expect(model.estimate == nil)
        #expect(model.trainingRating == 800)
        #expect(model.winRate == 0.5)
    }

    @Test func threeGamesGiveARatingThatDrivesTraining() throws {
        // Rookie Ron (800), wins as White and as Black, one loss: (980 + 980 + 620) / 3 = 860
        try save(result: .whiteWins)
        try save(result: .blackWins, user: .black, daysAgo: 1)
        try save(result: .blackWins, daysAgo: 2)
        let m = model
        #expect(m.estimate == 860)
        #expect(m.trainingRating == 860)
        #expect(m.gamesUntilRating == 0)
        #expect(m.tier == .knight)
    }

    @Test func unfinishedGamesAreListedButNotRated() throws {
        try save(result: .ongoing)
        try save(result: .draw, daysAgo: 1)
        let m = model
        #expect(m.games.count == 2)
        #expect(m.finishedCount == 1)
        #expect(m.winRate == 0)
    }

    @Test func onlyDraws() throws {
        for day in 0..<3 { try save(result: .draw, daysAgo: Double(day)) }
        #expect(model.estimate == 800)
        #expect(model.winRate == 0)
    }

    @Test func undecodableRecordIsSkipped() throws {
        try save(result: .whiteWins)
        let broken = try save(result: .whiteWins, daysAgo: 1)
        broken.snapshotData = Data("not json".utf8)
        try container.mainContext.save()
        #expect(model.games.count == 1)
        #expect(model.finishedCount == 1)
    }

    @Test func howYouMoveAndWhatKeepsCostingYou() throws {
        try save(result: .whiteWins, daysAgo: 2, accuracy: 70, verdicts: [
            verdict(ply: 1, mover: .white, .blunder, motifs: [.hangingPiece]),
            verdict(ply: 2, mover: .black, .blunder, motifs: [.allowedMate]),  // the bot's: ignored
        ])
        try save(result: .whiteWins, daysAgo: 1, accuracy: 80, verdicts: [
            verdict(ply: 1, mover: .white, .mistake, motifs: [.hangingPiece, .allowedFork]),
            verdict(ply: 3, mover: .white, .best, motifs: [.missedCapture]),  // not negative: ignored
            verdict(ply: 5, mover: .white, .inaccuracy),
        ])
        try save(result: .whiteWins, accuracy: 90, verdicts: [verdict(ply: 1, mover: .white, .best)])
        let m = model
        #expect(m.recentAccuracy?.value == 80)
        #expect(m.recentAccuracy?.games == 3)
        #expect(m.accuracyDelta == nil)
        // Oldest first, one column per game.
        #expect(m.moveQuality.map(\.blunders) == [1, 0, 0])
        #expect(m.moveQuality.map(\.mistakes) == [0, 1, 0])
        #expect(m.moveQuality.map(\.inaccuracies) == [0, 1, 0])
        #expect(m.moveQuality.map(\.good) == [0, 1, 1])
        #expect(m.weaknesses.map(\.motif) == [.hangingPiece, .allowedFork])
        #expect(m.weaknesses.first?.summary.count == 2)
        #expect(m.weaknesses.first?.games == 2)
        #expect(m.gradedGames == 3)
        // The example is the newest game's move, named with its bot.
        let top = try #require(m.weaknesses.first)
        #expect(top.example?.verdict.classification == .mistake)
        #expect(ProfileModel.context(for: top) == "Like e4 here — Rookie Ron could take it for free.")
    }

    @Test func accuracyDeltaComparesWithTheGamesBefore() throws {
        for day in 0..<10 { try save(result: .draw, daysAgo: Double(day), accuracy: 80, verdicts: [verdict(ply: 1, mover: .white, .best)]) }
        for day in 10..<12 { try save(result: .draw, daysAgo: Double(day), accuracy: 70, verdicts: [verdict(ply: 1, mover: .white, .best)]) }
        #expect(model.recentAccuracy?.games == 10)
        #expect(model.accuracyDelta == 10)
    }
}
