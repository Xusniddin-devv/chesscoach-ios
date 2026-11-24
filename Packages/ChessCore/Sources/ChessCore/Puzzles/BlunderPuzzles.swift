import Foundation

/// Turns the user's own mistakes into puzzles: the position before the bad move, with the
/// engine's best move (and best line, up to 3 plies) as the solution.
public enum BlunderPuzzles {
    public static let classes: Set<MoveClass> = [.mistake, .blunder, .miss]
    public static let maxPlies = 3

    public static func from(snapshot: GameSnapshot) -> [Puzzle] {
        // Prefer the full analysis; fall back to the live grades saved with the game.
        let verdicts = snapshot.analysis?.verdicts ?? snapshot.verdicts
        return verdicts
            .filter { $0.mover == snapshot.userColor && classes.contains($0.classification) }
            .compactMap { puzzle(from: $0, snapshot: snapshot) }
    }

    public static func id(gameId: UUID, ply: Int) -> String { "\(gameId.uuidString)-\(ply)" }

    static func puzzle(from verdict: Verdict, snapshot: GameSnapshot) -> Puzzle? {
        let facts = verdict.facts
        var line = facts.bestPv.isEmpty ? [verdict.bestMove] : facts.bestPv
        if line.first != verdict.bestMove, !verdict.bestMove.isEmpty { line = [verdict.bestMove] }
        line = Array(line.prefix(maxPlies))
        // The solution must end on the solver's move and every move must be legal.
        if line.count % 2 == 0 { line.removeLast() }
        guard !line.isEmpty, Rules.fen(startFen: facts.fenBefore, moves: line) != nil,
              line.first != verdict.uci else { return nil }

        let themes = verdict.motifs.map(\.rawValue) + [verdict.classification.rawValue]
        let rating = snapshot.playerRatingUsed
        let id = id(gameId: snapshot.id, ply: verdict.ply)

        // Show the opponent's previous move as the setup move when the game has it.
        let moveIndex = verdict.ply - 1
        if moveIndex >= 1, moveIndex < snapshot.moves.count, snapshot.moves[moveIndex] == verdict.uci,
           let before = Rules.fen(startFen: snapshot.startFen, moves: Array(snapshot.moves.prefix(moveIndex - 1))),
           Rules.apply(uci: snapshot.moves[moveIndex - 1], to: before)?.fenAfter == facts.fenBefore {
            return Puzzle(id: id, fen: before, moves: [snapshot.moves[moveIndex - 1]] + line,
                          rating: rating, themes: themes, hasSetupMove: true)
        }
        return Puzzle(id: id, fen: facts.fenBefore, moves: line, rating: rating, themes: themes, hasSetupMove: false)
    }
}
