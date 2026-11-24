import SwiftUI
import SwiftData
import ChessCore

/// Full-screen solver: rating and theme above the board, the board, then a status line or
/// the result card. Glass toolbar: close, hint.
struct PuzzleSessionView: View {
    let setup: PuzzleSessionSetup

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model: PuzzleSessionModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model { content(model) } else { DS.Color.background }
            }
            .background(DS.Color.background)
            .navigationTitle(setup.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hint", systemImage: "lightbulb") { model?.hint() }
                        .disabled(model?.interactive != true || model?.solver.hintShown == true)
                }
            }
        }
        .tint(DS.Color.text)
        .task {
            guard model == nil else { return }
            let next = PuzzleSessionModel(setup: setup)
            next.attach(context)
            model = next
            next.start()
        }
    }

    private func content(_ model: PuzzleSessionModel) -> some View {
        VStack(spacing: 0) {
            meta(model)
                .padding(.horizontal, DS.Spacing.m)
                .padding(.vertical, DS.Spacing.sm)
            BoardView(
                tracker: model.tracker,
                fen: model.solver.fen,
                orientation: model.orientation,
                interactive: model.interactive,
                lastMove: model.lastMove,
                squareTint: model.squareTint,
                badges: [:],
                arrows: model.arrows,
                onMove: model.move)
            .padding(.horizontal, DS.Spacing.s)
            .id(model.puzzle.id)  // a new puzzle is a new board: no pieces sliding across from the last one
            status(model)
                .padding(.horizontal, DS.Spacing.m)
                .padding(.top, DS.Spacing.m)
            Spacer(minLength: 0)
        }
        .animation(.snappy(duration: 0.25), value: model.solver.status)
        .onChange(of: model.finished) { _, done in if done { dismiss() } }
    }

    private func meta(_ model: PuzzleSessionModel) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if setup.puzzles.count > 1 {
                Text("\(model.index + 1) / \(setup.puzzles.count)")
                    .font(DS.Font.numeral)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            Text(themeLine(model.puzzle))
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
            Spacer()
            if model.setup.sources[model.puzzle.id] != "blunder" {
                Text(model.puzzle.rating, format: .number.grouping(.never))
                    .font(DS.Font.numeral)
                    .foregroundStyle(DS.Color.text)
                    .accessibilityLabel("Rating \(model.puzzle.rating)")
            }
        }
    }

    /// Themes are shown only once the puzzle is over: before that they give the answer away.
    private func themeLine(_ puzzle: Puzzle) -> String {
        guard let model, model.solver.status == .solved || model.solver.status == .failed else {
            return model?.setup.sources[puzzle.id] == "blunder" ? "From your game" : "Puzzle"
        }
        let names = puzzle.themes.filter { PuzzleBank.practiceThemes.contains($0) }.map(PuzzleBank.title(forTheme:))
        return names.isEmpty ? "Puzzle" : names.joined(separator: " · ")
    }

    @ViewBuilder
    private func status(_ model: PuzzleSessionModel) -> some View {
        let solver = model.solver
        switch solver.status {
        case .solved:
            ResultCard(title: "Solved", message: solvedMessage(model), positive: true) {
                PrimaryButton(title: model.isLast ? "Done" : "Next puzzle", action: model.next)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case .failed:
            ResultCard(title: "Not quite", message: failedMessage(model), positive: false) {
                HStack(spacing: DS.Spacing.sm) {
                    SecondaryButton(title: model.isLast ? "Done" : "Skip", action: model.next)
                    PrimaryButton(title: "Retry", action: model.retry)
                }
                if !model.showingSolution {
                    Button("Show solution") { model.showSolution() }
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.Color.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        default:
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(solver.status == .replying ? "Correct. Keep going." : "Find the best move for \(model.orientation == .white ? "White" : "Black")")
                    .font(DS.Font.headline)
                    .contentTransition(.opacity)
                if model.puzzle.solverMoveCount > 1 {
                    Text("Move \(model.moveNumber) of \(model.puzzle.solverMoveCount)")
                        .font(DS.Font.subheadline.monospacedDigit())
                        .foregroundStyle(DS.Color.textSecondary)
                } else if solver.hintShown {
                    Text("The piece to move is marked.")
                        .font(DS.Font.subheadline)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func solvedMessage(_ model: PuzzleSessionModel) -> String {
        if model.solver.solvedClean { return model.setup.kind == .review ? "You'll see it again in a few days." : "First try." }
        return model.solver.hintUsed ? "Solved with a hint. It will come back for review." : "Solved on a retry. It will come back for review."
    }

    private func failedMessage(_ model: PuzzleSessionModel) -> String {
        model.showingSolution ? "The arrow shows the move. Retry and play it." : "That move lets the chance go. Try again, or look at the solution."
    }
}
