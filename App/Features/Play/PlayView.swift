import SwiftUI
import SwiftData
import OSLog
import ChessCore

/// Full-screen game against a bot on the shared board scaffold: move strip, opponent bar,
/// board with eval bar (Training), user bar and a status line, centred between the top and
/// the flat action bar (resign · hint · back · forward · flip). A Training interrupt slides the coach
/// card up in place of the action bar. ‹ › and the strip show earlier positions read-only.
struct PlayView: View {
    let setup: PlaySetup

    @Environment(EngineHub.self) private var hub
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlayModel?
    @State private var confirmingResign = false
    @State private var showingResult = false
    @State private var saveFailed = false

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "uz.xq.chessc", category: "persistence")

    var body: some View {
        Group {
            if let model { content(model) } else { DS.Color.background }
        }
        .background(DS.Color.background.ignoresSafeArea())
        .tint(DS.Color.text)  // bar glyphs stay neutral; the accent is for the one primary action
        .task { if model == nil { begin() } }
        .onAppear { hub.isGameLive = true }
        .onDisappear { hub.isGameLive = false }
    }

    private func begin() {
        let next = PlayModel(setup: setup, hub: hub)
        model = next
        next.start()
        #if DEBUG
        DebugAutoplay.attachIfRequested(to: next, onFinished: done)
        #endif
    }

    // MARK: Layout

    private func content(_ model: PlayModel) -> some View {
        let session = model.session
        let shown = model.displayedPly
        return GameBoardScaffold(
            moves: model.stripItems,
            startFen: session.startFen,
            currentPly: shown > 0 ? shown : nil,
            onSelectPly: { ply in withAnimation(.snappy) { model.select(ply: ply) } },
            top: model.opponentBar,
            bottom: model.userBar,
            status: status(model),
            statusAccessory: statusAccessory(model),
            board: { board(model) },
            actions: { actionBar(model) },
            card: {
                if let verdict = model.interruption {
                    CoachCard(
                        verdict: verdict,
                        wording: hub.wording,
                        onTakeBack: session.takeBack,
                        onShowBest: session.showBest,
                        onContinue: session.continueAfterInterrupt)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            })
        .animation(.snappy(duration: 0.25), value: model.interruption)
        .onChange(of: model.interruption) { _, verdict in
            if verdict != nil { model.returnToLive() }  // the coach talks about the live position
        }
        .onChange(of: model.isOver) { _, over in
            guard over else { return }
            model.returnToLive()
            Task {
                try? await Task.sleep(for: .milliseconds(600))  // let the last move land first
                showingResult = true
            }
        }
        .sheet(isPresented: $showingResult) {
            GameOverSheet(model: model, saveFailed: saveFailed, onPlayAgain: playAgain, onDone: done,
                          onCloseWithoutSaving: closeWithoutSaving)
                .interactiveDismissDisabled()
        }
        .confirmationDialog("Resign this game?", isPresented: $confirmingResign, titleVisibility: .visible) {
            Button("Resign", role: .destructive) { session.resign() }
        }
    }

    private func board(_ model: PlayModel) -> some View {
        BoardView(
            tracker: model.displayedTracker,
            fen: model.displayedFen,
            orientation: model.orientation,
            interactive: model.interactive,
            lastMove: model.displayedLastMove.map { ($0.from, $0.to) },
            squareTint: model.squareTint,
            badges: model.badges,
            arrows: model.arrows,
            onMove: model.move)
        .overlay(alignment: .leading) {
            if model.session.mode == .training {  // Silent means no coaching during play
                // In the margin just left of the board, whatever the board's size.
                EvalBar(whiteCp: model.whiteCp, orientation: model.orientation)
                    .offset(x: -(EvalBar.width + 1))
            }
        }
    }

    private func status(_ model: PlayModel) -> String? {
        if model.session.hasEngineError && !model.isOver { return "The engine stopped." }
        return model.statusText
    }

    private func statusAccessory(_ model: PlayModel) -> BoardStatusAccessory? {
        if model.viewedPly != nil { return .backToLive(hasNewMoves: model.hasNewMovesWhileViewing) }
        if model.session.hasEngineError && !model.isOver { return .action("Retry", model.session.retry) }
        return nil
    }

    // MARK: Action bar

    private func actionBar(_ model: PlayModel) -> some View {
        GameActionBar {
            if model.hasUserMoves && !model.isOver {
                GameAction(title: "Resign", icon: "resign") { confirmingResign = true }
            } else {
                GameAction(title: "Close", icon: "close") { leave(model) }
            }
            if model.session.mode == .training {
                GameAction(title: "Hint", icon: "hint") { Task { await model.hint() } }
                    .disabled(!model.interactive || model.isHinting)
            }
            GameAction(title: "Back", icon: "back") { withAnimation(.snappy) { model.step(-1) } }
                .disabled(!model.canStepBack)
            GameAction(title: "Forward", icon: "forward") { withAnimation(.snappy) { model.step(1) } }
                .disabled(!model.canStepForward)
            GameAction(title: "Flip", icon: "flip") { withAnimation(.snappy) { model.flip() } }
        }
    }

    // MARK: Leaving

    private func leave(_ model: PlayModel) {
        if model.isOver { done() } else { dismiss() }
    }

    /// Saves the finished game, then moves on. The save waits for the last grades; if it
    /// fails, the sheet stays with an inline error and the next Done / Play again retries.
    private func saveThen(_ next: @escaping () -> Void) {
        guard let model else { return }
        Task {
            do {
                try await model.save(in: context)
                saveFailed = false
                next()
            } catch {
                Self.log.error("Saving the game failed: \(error.localizedDescription, privacy: .public)")
                saveFailed = true
            }
        }
    }

    private func done() {
        saveThen {
            showingResult = false
            dismiss()
        }
    }

    private func playAgain() {
        saveThen {
            showingResult = false
            begin()
        }
    }

    private func closeWithoutSaving() {
        showingResult = false
        dismiss()
    }
}

/// An inline failure with one action (engine retry, close without saving); no alerts.
struct InlineErrorRow: View {
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack {
            Text(message)
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.text)
            Spacer()
            Button(actionTitle, action: action)
                .font(DS.Font.headline)
                .foregroundStyle(DS.Color.accent)
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
    }
}
