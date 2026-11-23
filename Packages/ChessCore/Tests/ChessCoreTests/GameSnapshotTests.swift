import Foundation
import Testing
@testable import ChessCore

private let startFen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
private let knightFen = "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"

private func line(_ score: Score, _ pv: [String] = []) -> PVLine {
    PVLine(multipv: 1, depth: 14, score: score, pv: pv)
}

/// Negative verdict: Nf3-g5 hangs the knight to Qd8xg5 (hanging-piece motif).
private func hangingKnightVerdict() -> Verdict {
    classifyPlayed(PlayedMoveInput(
        fenBefore: knightFen,
        fenAfter: "r1bqkbnr/pppp1ppp/2n5/4p1N1/4P3/8/PPPP1PPP/RNBQKB1R b KQkq - 3 3",
        playedUci: "f3g5", playedSan: "Ng5",
        mover: .white, ply: 5,
        before: AnalysisResult(bestMove: "d2d4", lines: [line(Score(cp: 20), ["d2d4"])]),
        after: AnalysisResult(bestMove: "d8g5", lines: [line(Score(cp: 300), ["d8g5"])])))
}

/// Positive verdict from a position where White already has a forced mate.
private func matingVerdict() -> Verdict {
    classifyPlayed(PlayedMoveInput(
        fenBefore: startFen,
        fenAfter: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        playedUci: "e2e4", playedSan: "e4",
        mover: .white, ply: 1,
        before: AnalysisResult(bestMove: "e2e4", lines: [line(Score(mate: 3), ["e2e4"])]),
        after: AnalysisResult(bestMove: "e7e5", lines: [line(Score(mate: -3), ["e7e5"])]),
        ))
}

private func sampleSnapshot() -> GameSnapshot {
    GameSnapshot(
        id: UUID(uuidString: "6F1C2B3A-4D5E-4F60-8172-93A4B5C6D7E8")!,
        date: Date(timeIntervalSince1970: 1_790_000_000),
        botId: "bot-800",
        userColor: .white,
        mode: .training,
        startFen: startFen,
        moves: ["e2e4", "g1f3", "f3g5"],
        sans: ["e4", "Nf3", "Ng5"],
        result: .ongoing,
        verdicts: [matingVerdict(), hangingKnightVerdict()],
        analysisVersion: 1,
        playerRatingUsed: 800
    )
}

@Test func roundTripsThroughJSON() throws {
    let snapshot = sampleSnapshot()
    let data = try encodeSnapshot(snapshot)
    let decoded = try decodeSnapshot(data)

    #expect(decoded == snapshot)
    #expect(decoded.analysisVersion == 1)
    #expect(decoded.verdicts.count == 2)
    #expect(decoded.verdicts[1].motifs == [.hangingPiece])
    #expect(decoded.verdicts[0].mateBefore == 3)
}

@Test func encodingIsDeterministic() throws {
    let snapshot = sampleSnapshot()
    #expect(try encodeSnapshot(snapshot) == encodeSnapshot(snapshot))
}

@Test func roundTripsFractionalDate() throws {
    var snapshot = sampleSnapshot()
    snapshot.date = Date(timeIntervalSinceReferenceDate: 780_000_000.123456)
    #expect(try decodeSnapshot(encodeSnapshot(snapshot)) == snapshot)

    snapshot.date = Date.now
    #expect(try decodeSnapshot(encodeSnapshot(snapshot)) == snapshot)
}

// MARK: - Format stability

/// The sample snapshot as a mutable JSON object, so tests can drop or corrupt fields.
private func sampleJSON() throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: encodeSnapshot(sampleSnapshot())) as! [String: Any]
}

private func decode(_ json: [String: Any]) throws -> GameSnapshot {
    try decodeSnapshot(JSONSerialization.data(withJSONObject: json))
}

@Test func newSnapshotsCarrySchemaVersion1() throws {
    #expect(sampleSnapshot().schemaVersion == 1)
    #expect(try sampleJSON()["schemaVersion"] as? Int == 1)
}

@Test func decodesBlobMissingOptionalAndNewerFields() throws {
    var json = try sampleJSON()
    for key in ["schemaVersion", "sans", "verdicts", "analysisVersion", "playerRatingUsed", "analysis", "openingName"] {
        json.removeValue(forKey: key)
    }
    let decoded = try decode(json)
    let sample = sampleSnapshot()
    #expect(decoded.id == sample.id)
    #expect(decoded.date == sample.date)
    #expect(decoded.botId == sample.botId)
    #expect(decoded.userColor == sample.userColor)
    #expect(decoded.moves == sample.moves)
    #expect(decoded.schemaVersion == 1)
    #expect(decoded.startFen == sample.startFen)
    #expect(decoded.sans.isEmpty)
    #expect(decoded.verdicts.isEmpty)
    #expect(decoded.analysisVersion == 1)
    #expect(decoded.playerRatingUsed == PlayerProfile.defaultRating)
    #expect(decoded.mode == sample.mode)
    #expect(decoded.result == sample.result)
    #expect(decoded.analysis == nil)
    #expect(decoded.openingName == nil)
}

@Test func decodesVerdictMissingOptionalFields() throws {
    var json = try sampleJSON()
    var verdicts = json["verdicts"] as! [[String: Any]]
    for key in ["motifs", "bestLineSan", "bestSan", "mateBefore", "mateAfter"] {
        verdicts[1].removeValue(forKey: key)
    }
    var facts = verdicts[1]["facts"] as! [String: Any]
    for key in ["bestPv", "bestReplyUci", "mateForMoverBefore", "mateAgainstMoverAfter"] {
        facts.removeValue(forKey: key)
    }
    verdicts[1]["facts"] = facts
    json["verdicts"] = verdicts
    let v = try decode(json).verdicts[1]
    #expect(v.classification == hangingKnightVerdict().classification)
    #expect(v.motifs.isEmpty)
    #expect(v.bestLineSan.isEmpty)
    #expect(v.bestSan == v.bestMove)
    #expect(v.facts.bestPv.isEmpty)
    #expect(v.facts.bestReplyUci == "")
}

@Test func unknownFieldsAreIgnored() throws {
    var json = try sampleJSON()
    json["schemaVersion"] = 2
    json["somethingAddedLater"] = ["a": 1]
    var verdicts = json["verdicts"] as! [[String: Any]]
    verdicts[0]["somethingAddedLater"] = true
    json["verdicts"] = verdicts
    let decoded = try decode(json)
    #expect(decoded.schemaVersion == 2)
    #expect(decoded.verdicts.count == 2)
}

@Test func corruptVerdictIsDroppedNotTheGame() throws {
    var json = try sampleJSON()
    var verdicts = json["verdicts"] as! [[String: Any]]
    verdicts[0]["classification"] = "not-a-class"
    json["verdicts"] = verdicts + [["ply": "garbage"]]
    let decoded = try decode(json)
    #expect(decoded.moves == sampleSnapshot().moves)
    #expect(decoded.verdicts == [hangingKnightVerdict()])
}

@Test func unknownMotifIsDroppedNotTheVerdict() throws {
    var json = try sampleJSON()
    var verdicts = json["verdicts"] as! [[String: Any]]
    verdicts[1]["motifs"] = ["hanging-piece", "added-later"]
    json["verdicts"] = verdicts
    #expect(try decode(json).verdicts[1].motifs == [.hangingPiece])
}

@Test func missingCoreFieldStillFails() throws {
    var json = try sampleJSON()
    json.removeValue(forKey: "moves")
    #expect(throws: (any Error).self) { try decode(json) }
}

/// Stored raw values: changing one breaks every saved game.
@Test func storedRawValuesArePinned() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let results: [(GameResult, String)] = [(.whiteWins, "1-0"), (.blackWins, "0-1"), (.draw, "1/2-1/2"), (.ongoing, "*")]
    for (value, raw) in results {
        #expect(try encoder.encode([value]) == Data("[\"\(raw)\"]".utf8))
        #expect(try JSONDecoder().decode([GameResult].self, from: Data("[\"\(raw)\"]".utf8)) == [value])
    }
    let modes: [(PlayMode, String)] = [(.training, "training"), (.silent, "silent")]
    for (value, raw) in modes {
        #expect(try encoder.encode([value]) == Data("[\"\(raw)\"]".utf8))
        #expect(try JSONDecoder().decode([PlayMode].self, from: Data("[\"\(raw)\"]".utf8)) == [value])
    }
}

// MARK: - Required core fields and analysis

@Test func missingResultFailsToDecode() throws {
    var json = try sampleJSON()
    json.removeValue(forKey: "result")
    #expect(throws: (any Error).self) { try decode(json) }
}

@Test func missingStartFenFailsToDecode() throws {
    var json = try sampleJSON()
    json.removeValue(forKey: "startFen")
    #expect(throws: (any Error).self) { try decode(json) }
}

@Test func missingModeFailsToDecode() throws {
    var json = try sampleJSON()
    json.removeValue(forKey: "mode")
    #expect(throws: (any Error).self) { try decode(json) }
}

@Test func analysisRoundTrips() throws {
    var snapshot = sampleSnapshot()
    snapshot.openingName = "King's Pawn Game"
    snapshot.analysis = GameAnalysis(
        depth: 14,
        verdicts: [matingVerdict(), hangingKnightVerdict()],
        whiteWin: [50, 55.5, 60, 20],
        accuracyWhite: 87.5,
        accuracyBlack: 92.25)
    let decoded = try decodeSnapshot(encodeSnapshot(snapshot))
    #expect(decoded == snapshot)
    #expect(decoded.analysis?.version == GameAnalysis.currentVersion)
    #expect(decoded.analysis?.whiteWin.count == 4)
    #expect(decoded.openingName == "King's Pawn Game")
    #expect(GameAnalysis.currentVersion == 1)
}

@Test func oldBlobWithoutAnalysisDecodes() throws {
    var json = try sampleJSON()
    json.removeValue(forKey: "analysis")
    json.removeValue(forKey: "openingName")
    let decoded = try decode(json)
    #expect(decoded.analysis == nil)
    #expect(decoded.openingName == nil)
    #expect(decoded.verdicts.count == 2)
}

@Test func corruptAnalysisIsDroppedNotTheGame() throws {
    var json = try sampleJSON()
    json["analysis"] = ["depth": "garbage"]
    let decoded = try decode(json)
    #expect(decoded.analysis == nil)
    #expect(decoded.moves == sampleSnapshot().moves)
}
