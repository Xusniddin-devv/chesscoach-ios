import Foundation

public struct PlayedMoveInput: Sendable {
    public var fenBefore: String
    public var fenAfter: String
    public var playedUci: String
    public var playedSan: String
    public var mover: Piece.Color
    public var ply: Int
    public var before: AnalysisResult
    public var after: AnalysisResult

    public init(fenBefore: String, fenAfter: String, playedUci: String, playedSan: String,
                mover: Piece.Color, ply: Int, before: AnalysisResult, after: AnalysisResult) {
        self.fenBefore = fenBefore
        self.fenAfter = fenAfter
        self.playedUci = playedUci
        self.playedSan = playedSan
        self.mover = mover
        self.ply = ply
        self.before = before
        self.after = after
    }
}

public struct MoveFacts: Codable, Sendable, Equatable {
    public var fenBefore: String
    public var fenAfter: String
    public var playedUci: String
    public var playedSan: String
    public var bestUci: String
    public var bestPv: [String]
    public var bestReplyUci: String
    public var cpLoss: Int
    public var evalAfterWhiteCp: Int
    public var mateForMoverBefore: Int?
    public var mateAgainstMoverAfter: Int?
    public var moveNumber: Int
    public var mover: Piece.Color

    public init(fenBefore: String, fenAfter: String, playedUci: String, playedSan: String,
                bestUci: String, bestPv: [String], bestReplyUci: String, cpLoss: Int,
                evalAfterWhiteCp: Int, mateForMoverBefore: Int?, mateAgainstMoverAfter: Int?,
                moveNumber: Int, mover: Piece.Color) {
        self.fenBefore = fenBefore
        self.fenAfter = fenAfter
        self.playedUci = playedUci
        self.playedSan = playedSan
        self.bestUci = bestUci
        self.bestPv = bestPv
        self.bestReplyUci = bestReplyUci
        self.cpLoss = cpLoss
        self.evalAfterWhiteCp = evalAfterWhiteCp
        self.mateForMoverBefore = mateForMoverBefore
        self.mateAgainstMoverAfter = mateAgainstMoverAfter
        self.moveNumber = moveNumber
        self.mover = mover
    }
}

public struct Verdict: Codable, Sendable, Equatable {
    public var ply: Int
    public var san: String
    public var uci: String
    public var mover: Piece.Color
    public var classification: MoveClass
    public var cpLoss: Int
    public var winDrop: Double
    public var evalWhiteCp: Int
    public var mateBefore: Int?
    public var mateAfter: Int?
    public var bestMove: String
    public var bestSan: String
    public var bestLineSan: [String]
    public var motifs: [Motif]
    public var facts: MoveFacts
}

// Stored inside saved games (GameSnapshot): decoding is lenient so the format can grow.
// Fields added later must use `decodeIfPresent` with a default.

extension Verdict {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ply = try c.decode(Int.self, forKey: .ply)
        san = try c.decode(String.self, forKey: .san)
        uci = try c.decode(String.self, forKey: .uci)
        mover = try c.decode(Piece.Color.self, forKey: .mover)
        classification = try c.decode(MoveClass.self, forKey: .classification)
        cpLoss = try c.decode(Int.self, forKey: .cpLoss)
        winDrop = try c.decode(Double.self, forKey: .winDrop)
        evalWhiteCp = try c.decode(Int.self, forKey: .evalWhiteCp)
        bestMove = try c.decode(String.self, forKey: .bestMove)
        facts = try c.decode(MoveFacts.self, forKey: .facts)
        mateBefore = try c.decodeIfPresent(Int.self, forKey: .mateBefore)
        mateAfter = try c.decodeIfPresent(Int.self, forKey: .mateAfter)
        bestSan = try c.decodeIfPresent(String.self, forKey: .bestSan) ?? bestMove
        bestLineSan = try c.decodeIfPresent([String].self, forKey: .bestLineSan) ?? []
        // A motif added in a later version is unknown here: drop it, keep the verdict.
        motifs = (try c.decodeIfPresent([String].self, forKey: .motifs) ?? []).compactMap(Motif.init(rawValue:))
    }
}

extension MoveFacts {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fenBefore = try c.decode(String.self, forKey: .fenBefore)
        fenAfter = try c.decode(String.self, forKey: .fenAfter)
        playedUci = try c.decode(String.self, forKey: .playedUci)
        playedSan = try c.decode(String.self, forKey: .playedSan)
        bestUci = try c.decode(String.self, forKey: .bestUci)
        cpLoss = try c.decode(Int.self, forKey: .cpLoss)
        evalAfterWhiteCp = try c.decode(Int.self, forKey: .evalAfterWhiteCp)
        mover = try c.decode(Piece.Color.self, forKey: .mover)
        bestPv = try c.decodeIfPresent([String].self, forKey: .bestPv) ?? []
        bestReplyUci = try c.decodeIfPresent(String.self, forKey: .bestReplyUci) ?? ""
        mateForMoverBefore = try c.decodeIfPresent(Int.self, forKey: .mateForMoverBefore)
        mateAgainstMoverAfter = try c.decodeIfPresent(Int.self, forKey: .mateAgainstMoverAfter)
        moveNumber = try c.decodeIfPresent(Int.self, forKey: .moveNumber) ?? 1
    }
}

/// JS `Math.round` semantics: halves round toward +infinity.
private func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

private func sideToMove(fen: String) -> Piece.Color {
    fen.split(separator: " ").dropFirst().first == "b" ? .black : .white
}

private func moveNumber(fen: String) -> Int {
    let fields = fen.split(separator: " ")
    return fields.count >= 6 ? (Int(fields[5]) ?? 1) : 1
}

public func classifyPlayed(_ input: PlayedMoveInput) -> Verdict {
    let mover = input.mover
    let sideAfter = sideToMove(fen: input.fenAfter)
    let beforeTop = input.before.lines.first?.score ?? Score(cp: 0)
    let afterTop = input.after.lines.first?.score ?? Score(cp: 0)

    let s = toCp(beforeTop, sideToMove: mover)
    let c = toCp(afterTop, sideToMove: sideAfter)
    let u: Double = mover == .white ? 1 : -1

    let cpLossRaw = max(0, u * (s - c))
    let wasBest = input.before.bestMove == input.playedUci || cpLossRaw <= 5
    let gapToSecond: Double = input.before.lines.count >= 2
        ? max(0, u * (toCp(input.before.lines[0].score, sideToMove: mover)
                      - toCp(input.before.lines[1].score, sideToMove: mover)))
        : 0

    func moverWin(_ cp: Double) -> Double {
        mover == .white ? winPercent(cp) : 100 - winPercent(cp)
    }
    let winBefore = moverWin(s)
    let winDropRaw = max(0, winBefore - moverWin(c))
    let winAfter = winBefore - winDropRaw

    let hadMate = (beforeTop.mate ?? 0) > 0
    let mateBefore: Int? = hadMate ? beforeTop.mate : nil
    let mateAfter: Int? = (afterTop.mate ?? 0) > 0 ? afterTop.mate : nil

    let legalCount = Rules.legalMoveCount(fen: input.fenBefore) ?? 30
    let isBook = input.ply <= 8 && cpLossRaw <= 35

    let cls: MoveClass
    if legalCount <= 1 {
        cls = .forced
    } else if (hadMate || winBefore >= 85) && winAfter < 70 {
        cls = .miss
    } else if wasBest || cpLossRaw <= 30,
              winBefore < 90, winAfter >= 50,
              isSacrifice(fenBefore: input.fenBefore, fenAfter: input.fenAfter,
                          uci: input.playedUci, mover: mover) {
        cls = .brilliant
    } else if isBook {
        cls = .book
    } else if wasBest && gapToSecond >= 150 {
        cls = .great
    } else if wasBest {
        cls = .best
    } else if winDropRaw >= 20 {
        cls = .blunder
    } else if winDropRaw >= 10 {
        cls = .mistake
    } else if winDropRaw >= 5 {
        cls = .inaccuracy
    } else if cpLossRaw <= 20 {
        cls = .excellent
    } else {
        cls = .good
    }

    let bestUci = input.before.bestMove.isEmpty ? input.playedUci : input.before.bestMove
    let bestSan = Rules.apply(uci: bestUci, to: input.fenBefore)?.san ?? bestUci
    let bestPv = input.before.lines.first?.pv ?? []

    var bestLineSan: [String] = []
    var fen = input.fenAfter
    for uci in (input.after.lines.first?.pv ?? []).prefix(6) {
        guard let applied = Rules.apply(uci: uci, to: fen) else { break }
        bestLineSan.append(applied.san)
        fen = applied.fenAfter
    }

    let cpLoss = Int(jsRound(cpLossRaw))
    let facts = MoveFacts(
        fenBefore: input.fenBefore, fenAfter: input.fenAfter,
        playedUci: input.playedUci, playedSan: input.playedSan,
        bestUci: bestUci, bestPv: bestPv, bestReplyUci: input.after.bestMove,
        cpLoss: cpLoss, evalAfterWhiteCp: Int(jsRound(c)),
        mateForMoverBefore: mateBefore, mateAgainstMoverAfter: mateAfter,
        moveNumber: moveNumber(fen: input.fenBefore), mover: mover)

    return Verdict(
        ply: input.ply, san: input.playedSan, uci: input.playedUci, mover: mover,
        classification: cls, cpLoss: cpLoss,
        winDrop: jsRound(10 * winDropRaw) / 10,
        evalWhiteCp: Int(jsRound(c)), mateBefore: mateBefore, mateAfter: mateAfter,
        bestMove: bestUci, bestSan: bestSan, bestLineSan: bestLineSan,
        motifs: cls.isNegative ? detectMotifs(facts) : [], facts: facts)
}
