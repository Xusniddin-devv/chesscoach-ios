import SwiftUI
import SwiftData
import ChessCore

/// Full-screen solver on Play's layout (`TrainingBoardScaffold`): a flat top row (close,
/// one pip per puzzle, title, rating in mono), the prompt with the side to move, the board
/// centred, the status line, the coach's line, and the flat action bar
/// Hint · Retry · Solution · Next (Next turns accent once the puzzle is over).
/// Feedback lives on the board (Best / Mistake badge, like Review), in the status line and in
/// the coach's line, which explains the solution with square chips. No result card.
struct PuzzleSessionView: View {
    let setup: PuzzleSessionSetup

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model: PuzzleSessionModel?

    var body: some View {
        Group {
            if let model { content(model) } else { DS.Color.background }
        }
        .background(DS.Color.background.ignoresSafeArea())
        .task {
            guard model == nil else { return }
            let next = PuzzleSessionModel(setup: setup)
            next.attach(context)
            model = next
            next.start()
            #if DEBUG
            await Self.debugSolve(next)
            #endif
        }
    }

    #if DEBUG
    /// `-debugPuzzleSolve solve|fail|solution`: plays the first puzzle (screenshots).
    private static func debugSolve(_ model: PuzzleSessionModel) async {
        guard let mode = UserDefaults.standard.string(forKey: "debugPuzzleSolve") else { return }
        try? await Task.sleep(for: .seconds(1.5))
        if mode == "solve" {
            while let move = model.solver.expectedMove, model.solver.status == .solving {
                _ = model.move(move)
                try? await Task.sleep(for: .seconds(1))
            }
        } else {
            let wrong = Rules.legalMoves(fen: model.solver.fen).first { $0 != model.solver.expectedMove }
            if let wrong { _ = model.move(wrong) }
            if mode == "solution" { try? await Task.sleep(for: .seconds(0.5)); model.showSolution() }
        }
    }
    #endif

    private func content(_ model: PuzzleSessionModel) -> some View {
        TrainingBoardScaffold(
            prompt: prompt(model),
            side: model.orientation,
            status: status(model),
            header: {
                TrainingTopBar(
                    pips: model.outcomes, current: model.index, title: title(model),
                    figure: model.isOwnMistake ? nil : String(model.puzzle.rating),
                    figureLabel: "Rating \(model.puzzle.rating)") { dismiss() }
            },
            board: {
                BoardView(
                    tracker: model.tracker,
                    fen: model.solver.fen,
                    orientation: model.orientation,
                    interactive: model.interactive,
                    lastMove: model.lastMove,
                    squareTint: model.squareTint,
                    badges: model.badges,
                    arrows: model.arrows,
                    onMove: model.move)
                .id(model.puzzle.id)  // a new puzzle is a new board: no pieces sliding across from the last one
            },
            coach: { coach(model) },
            actions: { actionBar(model) })
        .animation(.snappy(duration: 0.25), value: model.solver.status)
        .animation(.snappy(duration: 0.25), value: model.showingSolution)
        .onChange(of: model.finished) { _, done in if done { dismiss() } }
    }

    // MARK: Words

    /// The session's name, and the puzzle's themes once it is over.
    private func title(_ model: PuzzleSessionModel) -> String {
        guard model.isOver else { return setup.title }
        let names = model.puzzle.themes.filter { PuzzleBank.practiceThemes.contains($0) }.map(PuzzleBank.title(forTheme:))
        return names.isEmpty ? setup.title : names.prefix(2).joined(separator: " · ")
    }

    /// "White to move · find the fork". The theme is named only when the player chose it.
    private func prompt(_ model: PuzzleSessionModel) -> String {
        let side = model.orientation == .white ? "White" : "Black"
        let task: String
        if model.isOwnMistake {
            task = "find the move you missed"
        } else if let theme = setup.theme {
            task = Self.task(forTheme: theme)
        } else {
            task = "find the best move"
        }
        return "\(side) to move · \(task)"
    }

    static func task(forTheme theme: String) -> String {
        switch theme {
        case "mateIn1": "mate in 1"
        case "mateIn2": "mate in 2"
        case "mateIn3": "mate in 3"
        case "fork": "find the fork"
        case "pin": "find the pin"
        case "skewer": "find the skewer"
        case "hangingPiece", "capturingDefender": "win material"
        case "discoveredAttack": "find the discovery"
        case "backRankMate": "mate on the back rank"
        case "endgame": "find the winning move"
        default: "find the best move"
        }
    }

    private func status(_ model: PuzzleSessionModel) -> String {
        let solver = model.solver
        switch solver.status {
        case .setup:
            return "Watch the last move"
        case .solving:
            if solver.hintShown { return "The piece to move is marked" }
            return model.puzzle.solverMoveCount > 1
                ? "Move \(model.moveNumber) of \(model.puzzle.solverMoveCount)" : "Your move"
        case .replying:
            return "Correct · keep going"
        case .solved:
            if solver.solvedClean { return model.setup.kind == .review ? "Solved · back in a few days" : "Solved · first try" }
            return solver.hintUsed ? "Solved with a hint · it comes back for review" : "Solved on a retry · it comes back for review"
        case .failed:
            return model.showingSolution ? "The arrow shows the move · Retry and play it" : "Not quite"
        }
    }

    /// The coach always has a line, so the band under the board is never empty: what just
    /// happened before the puzzle, then the explanation once it is over.
    @ViewBuilder
    private func coach(_ model: PuzzleSessionModel) -> some View {
        let solver = model.solver
        let explanation = PuzzleExplainer.line(for: model.puzzle)
        switch solver.status {
        case .solved:
            CoachBubble(pose: .pleased, text: explanation ?? "**Clean.** That was it.", avatarSize: 52)
        case .failed where model.showingSolution:
            CoachBubble(pose: .thinking, text: explanation ?? "The arrow shows the move.", avatarSize: 52)
        case .failed:
            CoachBubble(pose: .concerned, text: "That lets the chance go. Look at what the last move left open.", avatarSize: 52)
        case .replying:
            CoachBubble(pose: .pleased, text: "Good. Now finish it.", avatarSize: 52)
        default:
            CoachBubble(pose: .neutral, text: opening(model), avatarSize: 52)
        }
    }

    /// Before the first move: the opponent's last move (as a chip-aware line) or where the
    /// position comes from.
    private func opening(_ model: PuzzleSessionModel) -> String {
        if model.isOwnMistake { return "This is from your game. Last time it slipped by. Find the move now." }
        let puzzle = model.puzzle
        if puzzle.hasSetupMove, let setup = puzzle.moves.first,
           let san = Rules.apply(uci: setup, to: puzzle.fen)?.san {
            let side = model.orientation == .white ? "Black" : "White"
            return "\(side) just played **\(san)**. What does that allow?"
        }
        return "Look for checks, captures and threats first."
    }

    // MARK: Action bar

    private func actionBar(_ model: PuzzleSessionModel) -> some View {
        let solver = model.solver
        return GameActionBar {
            GameAction(title: "Hint", icon: "hint") { model.hint() }
                .disabled(!model.interactive || solver.hintShown)
            GameAction(title: "Retry", icon: "return") { withAnimation(.snappy) { model.retry() } }
                .disabled(solver.status != .failed)
            GameAction(title: "Solution", icon: "solution", isOn: model.showingSolution) {
                withAnimation(.snappy) { model.showSolution() }
            }
            .disabled(solver.status != .failed || model.showingSolution)
            GameAction(title: model.isLast ? "Done" : "Next", icon: "forward", prominent: model.isOver) {
                withAnimation(.snappy) { model.next() }
            }
            .accessibilityLabel(model.isLast ? "Done" : model.isOver ? "Next puzzle" : "Skip puzzle")
        }
    }
}
