import Foundation

public enum GameAnalyzerError: Error, Equatable {
    case illegalMove(ply: Int, uci: String)
    case invalidStartFen
}

/// Bulk both-colour analysis of one finished game: every position is searched once, then
/// each ply is classified from the search before and after it.
public struct GameAnalyzer: Sendable {
    public let engine: any ChessEngine
    public let depth: Int

    public init(engine: any ChessEngine, depth: Int = 14) {
        self.engine = engine
        self.depth = depth
    }

    /// Throws on any engine error (the caller may retry) and propagates `CancellationError`.
    /// `progress(done, total)` fires after each analysed position; total is `moves.count + 1`.
    public func analyze(startFen: String, moves: [String],
                        progress: @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> GameAnalysis {
        // Replay the game once: FEN, SAN and mover for every ply.
        var fens = [startFen]
        var sans: [String] = []
        var movers: [Piece.Color] = []
        for (i, uci) in moves.enumerated() {
            guard let applied = Rules.apply(uci: uci, to: fens[i]) else {
                throw GameAnalyzerError.illegalMove(ply: i, uci: uci)
            }
            movers.append(Self.sideToMove(fen: fens[i]))
            sans.append(applied.san)
            fens.append(applied.fenAfter)
        }

        let total = moves.count + 1
        var results: [AnalysisResult] = []
        for i in 0..<total {
            try Task.checkCancellation()
            let request = AnalysisRequest(startFen: startFen, moves: Array(moves.prefix(i)),
                                          depth: depth, multiPV: 2)
            results.append(try await engine.analyze(request))
            progress(i + 1, total)
        }

        let whiteWin = (0..<total).map { i -> Double in
            let score = results[i].lines.first?.score ?? Score(cp: 0)
            let w = winPercent(toCp(score, sideToMove: Self.sideToMove(fen: fens[i])))
            return w.isFinite ? min(max(w, 0), 100) : 50
        }

        let verdicts = moves.indices.map { i in
            classifyPlayed(PlayedMoveInput(
                fenBefore: fens[i], fenAfter: fens[i + 1], playedUci: moves[i], playedSan: sans[i],
                mover: movers[i], ply: i + 1, before: results[i], after: results[i + 1]))
        }

        let accuracy = gameAccuracy(whiteWin: whiteWin, movers: movers)
        return GameAnalysis(depth: depth, verdicts: verdicts, whiteWin: whiteWin,
                            accuracyWhite: accuracy.white.isFinite ? accuracy.white : 100,
                            accuracyBlack: accuracy.black.isFinite ? accuracy.black : 100)
    }

    private static func sideToMove(fen: String) -> Piece.Color {
        fen.split(separator: " ").dropFirst().first == "b" ? .black : .white
    }
}
