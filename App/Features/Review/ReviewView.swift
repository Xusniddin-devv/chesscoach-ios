import SwiftUI
import ChessCore

/// A saved game on the shared board scaffold: the classified move strip, both players'
/// accuracy in their bars, the selected move's class on the board, the eval bar, and the
/// coach's comment on the selected move in a card above the action bar (the full
/// explanation for the user's negative moves). The action bar: move list
/// (back to the game inside a branch) · best move · ‹ › · flip. Moves played on the board
/// try a line (a branch), graded live.
struct ReviewView: View {
    let record: GameRecord

    @Environment(EngineHub.self) private var hub
    @State private var model: ReviewModel?
    @State private var showingMoves = false

    var body: some View {
        Group {
            if let model { content(model) } else { DS.Color.background }
        }
        .background(DS.Color.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .tint(DS.Color.text)
        .task {
            if model == nil { model = hub.makeReview(record: record, wording: hub.wording) }
            await model?.start()
            #if DEBUG
            if let model { await DebugReview.apply(to: model) }
            if UserDefaults.standard.string(forKey: "debugReviewList") != nil { showingMoves = true }
            #endif
        }
        .onDisappear { model?.cancel() }
    }

    private var title: String {
        guard let model else { return "Review" }
        return "vs \(model.botName)"
    }

    private var subtitle: String {
        guard let model, model.isReadable else { return "" }
        return model.openingName ?? model.snapshot.date.formatted(date: .abbreviated, time: .omitted)
    }

    private func content(_ model: ReviewModel) -> some View {
        GameBoardScaffold(
            moves: model.stripItems,
            startFen: model.snapshot.startFen,
            currentPly: model.selectedPly > 0 ? model.selectedPly : nil,
            onSelectPly: { ply in withAnimation(.snappy) { model.select(ply: ply ?? 0) } },
            top: model.opponentBar,
            bottom: model.userBar,
            status: model.statusText,
            statusAccessory: accessory(model),
            cardPlacement: .aboveBar,
            board: { board(model) },
            actions: { actionBar(model) },
            card: {
                if let verdict = model.selectedVerdict, let text = model.explanation {
                    ExplanationCard(verdict: verdict, text: text)
                        .id(verdict.ply)
                        .transition(.opacity)
                }
            })
        .animation(.snappy(duration: 0.25), value: model.explanation)
        .sheet(isPresented: $showingMoves) {
            ReviewMoveList(model: model) { ply in
                withAnimation(.snappy) {
                    model.exitBranch()
                    model.select(ply: ply)
                }
                showingMoves = false
            }
        }
    }

    private func board(_ model: ReviewModel) -> some View {
        BoardView(
            tracker: model.displayedTracker,
            fen: model.displayedFen,
            orientation: model.orientation,
            interactive: model.interactive,
            lastMove: model.displayedLastMove.map { ($0.from, $0.to) },
            squareTint: model.squareTint,
            badges: model.badges,
            arrows: model.arrows,
            onMove: model.playBranchMove)
        .overlay(alignment: .leading) {
            if model.analysis != nil {
                EvalBar(whiteCp: model.whiteCp, orientation: model.orientation)
                    .offset(x: -(EvalBar.width + 1))
                    .transition(.opacity)
            }
        }
    }

    private func accessory(_ model: ReviewModel) -> BoardStatusAccessory? {
        if let progress = model.analysisProgress { return .progress(progress) }
        if model.analysisFailed {
            return .action("Retry") { Task { await model.start() } }
        }
        if model.isInBranch && model.grader.hasError { return .action("Retry", model.grader.retry) }
        return nil
    }

    // MARK: Action bar

    private func actionBar(_ model: ReviewModel) -> some View {
        GlassEffectContainer {
            HStack(spacing: 0) {
                ActionBarGroup {
                    // Inside a tried line the first button leads back to the game; the
                    // explanation card may cover the status line, never the bar.
                    if model.isInBranch {
                        ActionBarButton(title: "Back to game", systemImage: "arrow.uturn.backward") {
                            withAnimation(.snappy) { model.exitBranch() }
                        }
                    } else {
                        ActionBarButton(title: "All moves", systemImage: "list.bullet") { showingMoves = true }
                            .disabled(model.snapshot.moves.isEmpty)
                    }
                }
                Spacer(minLength: DS.Spacing.s)
                ActionBarGroup {
                    ActionBarButton(title: model.showsBest ? "Hide best move" : "Show best move",
                                    systemImage: model.showsBest && model.canShowBest ? "lightbulb.fill" : "lightbulb") {
                        withAnimation(.snappy) { model.showsBest.toggle() }
                    }
                    .disabled(!model.canShowBest)
                }
                Spacer(minLength: DS.Spacing.s)
                ActionBarGroup {
                    ActionBarButton(title: "Previous move", systemImage: "chevron.left") {
                        withAnimation(.snappy) { model.step(-1) }
                    }
                    .disabled(!model.canStepBack)
                    ActionBarButton(title: "Next move", systemImage: "chevron.right") {
                        withAnimation(.snappy) { model.step(1) }
                    }
                    .disabled(!model.canStepForward)
                }
                Spacer(minLength: DS.Spacing.s)
                ActionBarGroup {
                    ActionBarButton(title: "Flip board", systemImage: "arrow.up.arrow.down") {
                        withAnimation(.snappy) { model.flip() }
                    }
                }
            }
        }
    }
}

/// The selected move's class pill and the coach's comment. Opaque `surface` with a hairline
/// (content, not glass), floating just above the action bar.
private struct ExplanationCard: View {
    let verdict: Verdict
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            ClassPill(moveClass: verdict.classification)
            Text(text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.large).stroke(DS.Color.surface2, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
