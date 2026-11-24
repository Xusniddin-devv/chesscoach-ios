import SwiftUI
import SwiftData
import ChessCore

/// The analysis board on the shared scaffold: move strip with live grades, both colours'
/// bars, the eval bar, the shown move's grade in the status line. Flat action bar:
/// Edit (position editor) · Best (arrow) · Take back · ‹ › · Flip. "Deep" in the navigation
/// bar searches the shown position to depth 20.
struct FreeplayView: View {
    /// A saved line to continue; nil opens a fresh board.
    let record: GameRecord?

    @Environment(EngineHub.self) private var hub
    @Environment(\.modelContext) private var context
    @State private var model: FreeplayModel?
    @State private var editing = false

    var body: some View {
        Group {
            if let model { content(model) } else { DS.Color.background }
        }
        .background(DS.Color.background.ignoresSafeArea())
        .navigationTitle("Analysis board")
        .navigationSubtitle(model?.subtitle ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let model {
                    Button { model.deep.toggle() } label: {
                        Text("Deep")
                            .font(DS.Font.subheadline.weight(.semibold))
                            .foregroundStyle(model.deep ? DS.Color.accent : DS.Color.text)
                    }
                    .accessibilityLabel("Deep analysis")
                    .accessibilityValue(model.deep ? "On, depth 20" : "Off, depth 14")
                }
            }
        }
        .tint(DS.Color.text)
        .task {
            if model == nil {
                model = FreeplayModel(engine: hub.engine, record: record, context: context)
                #if DEBUG
                if let model { DebugFreeplay.apply(to: model) }
                #endif
            }
            model?.refreshEval()
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "debugEditor") { editing = true }
            #endif
        }
        .onDisappear {
            model?.save()
            model?.cancel()
        }
    }

    private func content(_ model: FreeplayModel) -> some View {
        GameBoardScaffold(
            moves: model.stripItems,
            startFen: model.startFen,
            currentPly: model.selectedPly > 0 ? model.selectedPly : nil,
            onSelectPly: { ply in withAnimation(.snappy) { model.select(ply: ply ?? model.moves.count) } },
            top: model.bar(for: model.orientation.opposite),
            bottom: model.bar(for: model.orientation),
            status: model.statusText,
            statusAccessory: model.grader.hasError ? .action("Retry", model.grader.retry) : nil,
            board: { board(model) },
            actions: { actionBar(model) })
        .onChange(of: model.grader.verdicts.count) { model.save() }
        .fullScreenCover(isPresented: $editing) {
            PositionEditorView(fen: model.displayedFen) { fen in
                withAnimation(.snappy) { model.reset(to: fen) }
            }
        }
    }

    private func board(_ model: FreeplayModel) -> some View {
        BoardView(
            tracker: model.displayedTracker,
            fen: model.displayedFen,
            orientation: model.orientation,
            interactive: model.interactive,
            lastMove: model.displayedLastMove.map { ($0.from, $0.to) },
            squareTint: model.squareTint,
            badges: model.badges,
            arrows: model.arrows,
            onMove: { uci in withAnimation(.snappy) { model.play(uci) } })
        .overlay(alignment: .leading) {
            EvalBar(whiteCp: model.whiteCp, orientation: model.orientation)
                .offset(x: -(EvalBar.width + 1))
        }
    }

    private func actionBar(_ model: FreeplayModel) -> some View {
        GameActionBar {
            GameAction(title: "Edit", icon: "edit") { editing = true }
                .accessibilityLabel("Edit position")
            GameAction(title: "Best", icon: "hint", isOn: model.showsBest) {
                withAnimation(.snappy) { model.showsBest.toggle() }
            }
            .disabled(model.isOver)
            .accessibilityLabel(model.showsBest ? "Hide best move" : "Show best move")
            GameAction(title: "Take back", icon: "return") { withAnimation(.snappy) { model.takeBack() } }
                .disabled(!model.canTakeBack)
            GameAction(title: "Back", icon: "back") { withAnimation(.snappy) { model.step(-1) } }
                .disabled(!model.canStepBack)
            GameAction(title: "Forward", icon: "forward") { withAnimation(.snappy) { model.step(1) } }
                .disabled(!model.canStepForward)
            GameAction(title: "Flip", icon: "flip") { withAnimation(.snappy) { model.flip() } }
        }
    }
}

#if DEBUG
/// Launch arguments for screenshots: `-debugFreeplay "e2e4 e7e5 …"` plays a line;
/// `-debugFreeplayBest YES` shows the best-move arrow; `-debugEditor YES` opens the editor.
enum DebugFreeplay {
    static var requested: Bool {
        UserDefaults.standard.string(forKey: "debugFreeplay") != nil || UserDefaults.standard.bool(forKey: "debugEditor")
    }

    @MainActor static func apply(to model: FreeplayModel) {
        guard let line = UserDefaults.standard.string(forKey: "debugFreeplay") else { return }
        if !line.isEmpty, model.moves.isEmpty {
            for uci in line.split(separator: " ") { model.play(String(uci)) }
        }
        if UserDefaults.standard.bool(forKey: "debugFreeplayBest") { model.showsBest = true }
        if let back = Int(UserDefaults.standard.string(forKey: "debugFreeplayBack") ?? "") { model.step(-back) }
    }
}
#endif
