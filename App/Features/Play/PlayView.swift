import SwiftUI
import SwiftData
import ChessCore

/// Full-screen game against a bot: opponent row, board with eval bar, user row, and under
/// them the coach card (Training interrupts), an engine retry row or a quiet status line.
/// Glass toolbar: resign (or close before the first move), hint in Training, flip.
struct PlayView: View {
    let setup: PlaySetup

    @Environment(EngineHub.self) private var hub
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlayModel?
    @State private var confirmingResign = false
    @State private var showingResult = false

    var body: some View {
        NavigationStack {
            Group {
                if let model { content(model) } else { DS.Color.background }
            }
            .background(DS.Color.background)
            .toolbar { if let model { toolbar(model) } }
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(DS.Color.text)  // toolbar glyphs stay neutral; the accent is for the one primary action
        .task { if model == nil { begin() } }
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
        let botColor = session.userColor.opposite
        return VStack(spacing: 0) {
            PlayerRow(captured: model.captured(by: botColor), lead: model.materialLead(for: botColor)) {
                AvatarTile(bot: model.bot, size: 32)
            } name: {
                Text(model.bot.name)
                Text(model.bot.elo, format: .number.grouping(.never))
                    .font(DS.Font.numeral)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            board(model)
            PlayerRow(captured: model.captured(by: session.userColor), lead: model.materialLead(for: session.userColor)) {
                UserTile()
            } name: {
                Text("You")
            }
            status(model)
                .padding(.horizontal, DS.Spacing.m)
                .padding(.top, DS.Spacing.s)
            Spacer(minLength: 0)
        }
        .animation(.snappy(duration: 0.25), value: model.interruption)
        .onChange(of: model.isOver) { _, over in
            guard over else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(600))  // let the last move land first
                showingResult = true
            }
        }
        .sheet(isPresented: $showingResult) {
            GameOverSheet(model: model, onPlayAgain: playAgain, onDone: done)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .interactiveDismissDisabled()
        }
        .confirmationDialog("Resign this game?", isPresented: $confirmingResign, titleVisibility: .visible) {
            Button("Resign", role: .destructive) { session.resign() }
        }
    }

    private func board(_ model: PlayModel) -> some View {
        BoardView(
            tracker: model.session.tracker,
            fen: model.session.fen,
            orientation: model.orientation,
            interactive: model.interactive,
            lastMove: model.session.lastMove.map { ($0.from, $0.to) },
            squareTint: model.squareTint,
            badges: model.badges,
            arrows: model.arrows,
            onMove: model.move)
        .padding(.horizontal, DS.Spacing.s)
        .overlay(alignment: .leading) {
            EvalBar(whiteCp: model.whiteCp, orientation: model.orientation)
                .padding(.leading, 1)
        }
    }

    @ViewBuilder
    private func status(_ model: PlayModel) -> some View {
        let session = model.session
        if let verdict = model.interruption {
            CoachCard(
                verdict: verdict,
                onTakeBack: session.takeBack,
                onShowBest: session.showBest,
                onContinue: session.continueAfterInterrupt)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if session.hasEngineError && !model.isOver {
            EngineErrorRow(message: "The engine stopped.") { session.retry() }
        } else {
            Text(statusLine(model))
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
        }
    }

    private func statusLine(_ model: PlayModel) -> String {
        if model.hintUnavailable { return "Hint unavailable" }
        switch model.session.phase {
        case .botThinking: return "\(model.bot.name) is thinking"
        case .grading: return "Checking your move"
        default: return " "
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func toolbar(_ model: PlayModel) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if model.hasUserMoves && !model.isOver {
                Button("Resign", systemImage: "flag") { confirmingResign = true }
            } else {
                Button("Close", systemImage: "xmark") { leave(model) }
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if model.session.mode == .training {
                Button("Hint", systemImage: "lightbulb") { Task { await model.hint() } }
                    .disabled(!model.interactive || model.isHinting)
            }
            Button("Flip board", systemImage: "arrow.up.arrow.down") {
                withAnimation(.snappy) { model.flip() }
            }
        }
    }

    // MARK: Leaving

    /// Saves in the background (the save waits for the last grades) and goes on at once.
    private func save(_ model: PlayModel) {
        guard model.hasUserMoves || model.isOver else { return }
        let context = context
        Task { try? await model.save(in: context) }
    }

    private func leave(_ model: PlayModel) {
        if model.isOver { save(model) }
        dismiss()
    }

    private func done() {
        showingResult = false
        if let model { leave(model) }
    }

    private func playAgain() {
        if let model { save(model) }
        showingResult = false
        begin()
    }
}

/// One player: avatar, name and Elo on the left; what they have captured and their material
/// lead on the right.
private struct PlayerRow<Avatar: View, Name: View>: View {
    let captured: [Piece]
    let lead: Int
    @ViewBuilder var avatar: () -> Avatar
    @ViewBuilder var name: () -> Name

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            avatar()
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                name()
            }
            .font(DS.Font.headline)
            .foregroundStyle(DS.Color.text)
            .lineLimit(1)
            Spacer(minLength: DS.Spacing.s)
            CapturedTray(pieces: captured, lead: lead)
        }
        .frame(height: 44)
        .padding(.horizontal, DS.Spacing.m)
        .accessibilityElement(children: .combine)
    }
}

/// Small piece images, grouped by kind with same-kind pieces overlapping, then "+N".
private struct CapturedTray: View {
    let pieces: [Piece]
    let lead: Int

    private static let size: CGFloat = 22

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                HStack(spacing: -Self.size * 0.55) {
                    ForEach(0..<group.count, id: \.self) { _ in
                        PieceImage(piece: group.piece).frame(width: Self.size, height: Self.size)
                    }
                }
            }
            if lead > 0 {
                Text("+\(lead)")
                    .font(DS.Font.caption.monospaced().weight(.medium))
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(.leading, DS.Spacing.xs)
            }
        }
        .accessibilityHidden(true)
    }

    private var groups: [(piece: Piece, count: Int)] {
        var result: [(piece: Piece, count: Int)] = []
        for piece in pieces {
            if let last = result.last, last.piece.kind == piece.kind {
                result[result.count - 1].count += 1
            } else {
                result.append((piece, 1))
            }
        }
        return result
    }
}

/// An inline engine failure with a retry; no alerts.
struct EngineErrorRow: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack {
            Text(message)
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.text)
            Spacer()
            Button("Retry", action: retry)
                .font(DS.Font.headline)
                .foregroundStyle(DS.Color.accent)
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
    }
}
