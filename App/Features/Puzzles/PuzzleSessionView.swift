import SwiftUI
import SwiftData
import ChessCore

/// The puzzle solver on the shared `TrainingFrame`: X + one progress segment per puzzle +
/// the puzzle rating in mono; the coach says what to find ("White to move. Find the fork.",
/// square chips); the board edge to edge, centred; the hint and a chunky Continue. The verdict
/// slides up as a full-width band — accent "Solved first try · +8" with the Best / Brilliant
/// badge on the square, or red "Not quite. [Nf5+] was the fork." with Retry / Show solution.
struct PuzzleSessionView: View {
    let setup: PuzzleSessionSetup

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model: PuzzleSessionModel?

    var body: some View {
        Group {
            if let model { frame(model) } else { DS.Color.background.ignoresSafeArea() }
        }
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

    private func frame(_ model: PuzzleSessionModel) -> some View {
        TrainingFrame(
            segments: segments(model),
            figure: model.isOwnMistake ? nil : String(model.puzzle.rating),
            figureLabel: "Puzzle rating \(model.puzzle.rating)",
            pose: pose(model),
            lines: lines(model),
            band: band(model),
            onClose: { dismiss() },
            hintEnabled: model.interactive && !model.solver.hintShown,
            onHint: { withAnimation(.snappy) { model.hint() } },
            bottomTitle: model.isOver ? "Continue" : "Check",
            bottomEnabled: false,
            onBottom: {},
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
                .id(model.puzzle.id)  // a new puzzle is a new board: no pieces sliding across
            },
            answers: { EmptyView() })
        .animation(.snappy(duration: 0.25), value: model.solver.status)
        .onChange(of: model.finished) { _, done in if done { dismiss() } }
    }

    // MARK: State → words

    private func segments(_ model: PuzzleSessionModel) -> [ProgressSegment] {
        model.outcomes.enumerated().map { i, outcome in
            switch outcome {
            case true?: .done
            case false?: .missed
            case nil: i == model.index ? .current : .open
            }
        }
    }

    private func pose(_ model: PuzzleSessionModel) -> CoachPose {
        switch model.solver.status {
        case .solved, .replying: .pleased
        case .failed: model.showingSolution ? .thinking : .concerned
        default: model.solver.hintShown ? .thinking : .neutral
        }
    }

    private func side(_ model: PuzzleSessionModel) -> String { model.orientation == .white ? "White" : "Black" }

    /// "White to move. Find the fork."
    private func task(_ model: PuzzleSessionModel) -> String {
        if model.isOwnMistake { return "\(side(model)) to move. **Find the move you missed** in your game." }
        let goal = model.theme.map(Self.goal(forTheme:)) ?? "Find the best move."
        return "\(side(model)) to move. **\(goal)**"
    }

    static func goal(forTheme theme: String) -> String {
        switch theme {
        case "mateIn1": "Mate in one."
        case "mateIn2": "Mate in two."
        case "mateIn3": "Mate in three."
        case "fork": "Find the fork."
        case "pin": "Find the pin."
        case "skewer": "Find the skewer."
        case "hangingPiece": "Win the loose piece."
        case "capturingDefender": "Remove the defender."
        case "discoveredAttack": "Find the discovery."
        case "backRankMate": "Mate on the back rank."
        case "endgame": "Find the winning move."
        default: "Find the best move."
        }
    }

    /// What the theme calls the answer, for "Not quite. [Nf5+] was the fork."
    static func answerName(forTheme theme: String?) -> String {
        switch theme {
        case "mateIn1", "mateIn2", "mateIn3", "backRankMate": "the mate"
        case "fork": "the fork"
        case "pin": "the pin"
        case "skewer": "the skewer"
        case "discoveredAttack": "the discovery"
        default: "the move"
        }
    }

    private func lines(_ model: PuzzleSessionModel) -> [String] {
        let puzzle = model.puzzle
        var lines: [String] = []
        if puzzle.hasSetupMove, let setupMove = puzzle.moves.first,
           let san = Rules.apply(uci: setupMove, to: puzzle.fen)?.san {
            lines.append("\(model.orientation == .white ? "Black" : "White") played [\(san)].")
        }
        lines.append(task(model))
        let solver = model.solver
        switch solver.status {
        case .solving where solver.hintShown:
            if let square = solver.hintSquare { lines.append("Start with the piece on [\(square.notation)].") }
        case .replying:
            lines.append("Good. Now finish it.")
        case .solved:
            lines.append(PuzzleExplainer.line(for: puzzle) ?? "**That's it.**")
        case .failed:
            lines.append(model.showingSolution
                         ? (PuzzleExplainer.line(for: puzzle) ?? "The arrow shows the move.")
                         : "That lets the chance go. Look at what the last move left open.")
        default:
            break
        }
        return lines
    }

    // MARK: Band

    private func band(_ model: PuzzleSessionModel) -> TrainingBand? {
        let solver = model.solver
        let next = model.isLast ? "Done" : "Continue"
        switch solver.status {
        case .solved:
            let title: String
            if solver.solvedClean {
                let points = model.ratingDelta.map { " · " + Self.signed($0) } ?? ""
                title = "Solved first try\(points)"
            } else {
                title = solver.hintUsed ? "Solved with a hint" : "Solved on a retry"
            }
            return TrainingBand(id: "solved-\(model.puzzle.id)", kind: .success, title: title,
                                detail: solver.solvedClean ? nil : "It comes back for review.",
                                primary: next, onPrimary: { withAnimation(.snappy) { model.next() } })
        case .failed:
            let points = model.ratingDelta.map { " · " + Self.signed($0) } ?? ""
            let answer = expectedSan(model).map { "[\($0)] was \(Self.answerName(forTheme: model.theme))." } ?? ""
            return TrainingBand(
                id: "failed-\(model.puzzle.id)-\(model.showingSolution)", kind: .failure, title: "Not quite\(points)",
                detail: model.showingSolution ? "The arrow shows it. Play it on the board." : answer,
                primary: "Retry", onPrimary: { withAnimation(.snappy) { model.retry() } },
                secondary: model.showingSolution ? (model.isLast ? "Done" : "Skip") : "Show solution",
                onSecondary: {
                    withAnimation(.snappy) {
                        if model.showingSolution { model.next() } else { model.showSolution() }
                    }
                })
        default:
            return nil
        }
    }

    /// "+8", "−6" (a real minus sign).
    static func signed(_ n: Int) -> String { n >= 0 ? "+\(n)" : "\u{2212}\(abs(n))" }

    private func expectedSan(_ model: PuzzleSessionModel) -> String? {
        let puzzle = model.puzzle
        guard let fen = puzzle.solvingFen, puzzle.moves.indices.contains(puzzle.firstSolverIndex) else { return nil }
        return Rules.apply(uci: puzzle.moves[puzzle.firstSolverIndex], to: fen)?.san
    }

    #if DEBUG
    /// `-debugPuzzleSolve solve|fail|solution|hint`: plays the first puzzle (screenshots).
    private static func debugSolve(_ model: PuzzleSessionModel) async {
        guard let mode = UserDefaults.standard.string(forKey: "debugPuzzleSolve") else { return }
        try? await Task.sleep(for: .seconds(1.5))
        switch mode {
        case "solve":
            while let move = model.solver.expectedMove, model.solver.status == .solving {
                _ = model.move(move)
                try? await Task.sleep(for: .seconds(1))
            }
        case "hint":
            model.hint()
        default:
            if let wrong = Rules.legalMoves(fen: model.solver.fen).first(where: { $0 != model.solver.expectedMove }) {
                _ = model.move(wrong)
            }
            if mode == "solution" { try? await Task.sleep(for: .seconds(0.6)); model.showSolution() }
        }
    }
    #endif
}
