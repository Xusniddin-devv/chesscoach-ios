import SwiftUI
import ChessCore

/// "Guess the move" on the shared board scaffold. A card in place of the action bar picks the
/// side, then reveals each guess (your move, the game's move, the best move, the points); the
/// flat bar while guessing: End · Skip · Flip. When every move is guessed, the score.
struct GuessView: View {
    @State var model: GuessModel
    let onDone: () -> Void

    var body: some View {
        Group {
            if model.phase == .finished {
                GuessScoreView(model: model, onAgain: { withAnimation(.snappy) { model.restart() } }, onDone: onDone)
                    .transition(.opacity)
            } else {
                board
            }
        }
        .background(DS.Color.background.ignoresSafeArea())
        .navigationTitle("Guess the move")
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .tint(DS.Color.text)
        .onDisappear { model.cancel() }
        #if DEBUG
        .task { await DebugGuess.apply(to: model) }
        #endif
    }

    private var subtitle: String {
        switch model.phase {
        case .choosing, .finished: return "vs \(model.opponentName)"
        default:
            let progress = model.progress
            return "\(model.name(of: model.side)) as \(model.side == .white ? "White" : "Black") · \(progress.done) / \(progress.total)"
        }
    }

    private var board: some View {
        GameBoardScaffold(
            moves: [],
            startFen: model.snapshot.startFen,
            currentPly: nil,
            onSelectPly: { _ in },
            top: model.bar(for: model.orientation.opposite),
            bottom: model.bar(for: model.orientation),
            status: model.statusText,
            statusAccessory: isFailed ? .action("Retry", model.retry) : nil,
            board: {
                BoardView(
                    tracker: model.displayedTracker,
                    fen: model.displayedFen,
                    orientation: model.orientation,
                    interactive: model.interactive,
                    lastMove: model.lastMove,
                    squareTint: [:],
                    badges: model.badges,
                    arrows: model.arrows,
                    onMove: { model.guess($0) })
            },
            actions: {
                GameActionBar {
                    GameAction(title: "End", icon: "close") { withAnimation(.snappy) { model.finish() } }
                        .disabled(model.results.isEmpty)
                        .accessibilityLabel("End and see the score")
                    GameAction(title: "Skip", icon: "forward") { withAnimation(.snappy) { model.skip() } }
                        .disabled(model.phase != .guessing && !isFailed)
                        .accessibilityLabel("Skip this move")
                    GameAction(title: "Flip", icon: "flip") { withAnimation(.snappy) { model.orientation = model.orientation.opposite } }
                }
            },
            card: {
                if model.phase == .choosing {
                    GuessIntroCard(model: model)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let result = model.revealed {
                    GuessRevealCard(result: result, mover: model.name(of: model.side),
                                    isLast: model.guessPlies.last == result.ply) {
                        withAnimation(.snappy) { model.next() }
                    }
                    .id(result.ply)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            })
        .animation(.snappy(duration: 0.3), value: model.phase)
    }

    private var isFailed: Bool { if case .failed = model.phase { true } else { false } }
}

// MARK: Cards

/// The card's shell: opaque `surface`, 1 pt `surface2` hairline, `Radius.large` (the coach
/// card's language: content, not glass).
private struct GuessCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) { content }
            .padding(DS.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.large).stroke(DS.Color.surface2, lineWidth: 1))
    }
}

/// Pick a side, then Start.
private struct GuessIntroCard: View {
    @Bindable var model: GuessModel

    var body: some View {
        GuessCard {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Whose moves will you guess?")
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.text)
                Text("At each move, play what you would. Best move 3 points, close 2, near 1.")
                    .font(DS.Font.subheadline)
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: DS.Spacing.s) {
                sideOption(.white)
                sideOption(.black)
            }
            PrimaryButton(title: "Start") { withAnimation(.snappy) { model.start() } }
        }
    }

    private func sideOption(_ color: Piece.Color) -> some View {
        let selected = model.side == color
        let isUser = color == model.snapshot.userColor
        return Button {
            withAnimation(.snappy(duration: 0.2)) { model.side = color; model.orientation = color }
        } label: {
            HStack(spacing: DS.Spacing.s) {
                AvatarImage(asset: (isUser ? model.userAvatar : model.opponentAvatar) ?? RatingTier.pawn.avatarAsset, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.name(of: color))
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.Color.text)
                    Text("\(color == .white ? "White" : "Black") · \(model.plies(for: color).count) moves")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Spacing.s)
            .background(DS.Color.surface2.opacity(selected ? 1 : 0.5), in: RoundedRectangle(cornerRadius: DS.Radius.medium))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.medium).stroke(selected ? DS.Color.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Your move, the game's move, the best move — each with its badge disc — and the points.
private struct GuessRevealCard: View {
    let result: GuessResult
    let mover: String
    let isLast: Bool
    let onNext: () -> Void

    var body: some View {
        GuessCard {
            HStack(alignment: .top, spacing: DS.Spacing.m) {
                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                    row("Your move", san: result.guessSan, moveClass: result.guessClass)
                    row(mover == "You" ? "You played" : "\(mover) played", san: result.playedSan, moveClass: result.playedClass)
                    row("Best", san: result.bestSan, moveClass: .best)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("+\(result.points)")
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundStyle(result.points == GuessScoring.maxPoints ? DS.Color.accent : DS.Color.text)
                        .contentTransition(.numericText())
                    Text(result.points == 1 ? "point" : "points")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            PrimaryButton(title: isLast ? "See your score" : "Next move", action: onNext)
        }
    }

    private func row(_ label: String, san: String, moveClass: MoveClass) -> some View {
        HStack(spacing: DS.Spacing.s) {
            MoveBadge(moveClass: moveClass)
            Text(san)
                .font(DS.Font.headline)
                .foregroundStyle(DS.Color.text)
                .frame(minWidth: 52, alignment: .leading)
            Text(label)
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Score

/// The final score: one plain heavy number, the moves as a row of result chips (badge disc,
/// your move, points), and how the game's own moves would have scored. No gauge.
struct GuessScoreView: View {
    let model: GuessModel
    let onAgain: () -> Void
    let onDone: () -> Void

    var body: some View {
        let total = model.total
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("Your score")
                            .font(DS.Font.subheadline)
                            .foregroundStyle(DS.Color.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                            Text("\(total.points)")
                                .font(.system(size: 96, weight: .heavy))
                                .tracking(-4)
                                .foregroundStyle(DS.Color.text)
                            Text("of \(total.max)")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                        Text(summary)
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !model.results.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            Text("Move by move")
                                .font(.system(size: 20, weight: .semibold))
                                .tracking(-0.3)
                                .foregroundStyle(DS.Color.text)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: DS.Spacing.s)],
                                      alignment: .leading, spacing: DS.Spacing.s) {
                                ForEach(model.results) { result in chip(result) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.l)
            }
            VStack(spacing: DS.Spacing.s) {
                PrimaryButton(title: "Back to review", action: onDone)
                SecondaryButton(title: "Try again", action: onAgain)
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.bottom, DS.Spacing.s)
        }
    }

    /// "You found the best move 4 times. Your game's moves would have scored 15."
    private var summary: String {
        guard !model.results.isEmpty else { return "No moves guessed." }
        let best = model.bestCount
        let found = best == 0 ? "You didn't find the best move this time." :
            "You found the best move \(best == 1 ? "once" : "\(best) times")."
        let who = model.side == model.snapshot.userColor ? "Your moves in the game" : "\(model.opponentName)'s moves"
        return "\(found) \(who) would have scored \(model.gameTotal)."
    }

    private func chip(_ result: GuessResult) -> some View {
        HStack(spacing: 6) {
            MoveBadge(moveClass: result.guessClass)
                .scaleEffect(0.85)
                .frame(width: 22, height: 22)
            Text(result.guessSan)
                .font(DS.Font.subheadline.weight(.semibold))
                .foregroundStyle(DS.Color.text)
                .lineLimit(1)
            Spacer(minLength: 2)
            Text("\(result.points)")
                .font(DS.Font.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(result.points == GuessScoring.maxPoints ? DS.Color.accent : DS.Color.textSecondary)
        }
        .padding(.leading, 6)
        .padding(.trailing, DS.Spacing.sm)
        .frame(height: 38)
        .background(DS.Color.surface, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Move \((result.ply + 1) / 2), \(result.guessSan), \(result.guessClass.label), \(result.points) points")
    }
}

#if DEBUG
/// `-debugGuess N` starts guessing the user's side and plays the game's own moves for the
/// first N plies (bests where `-debugGuessBest YES`), stopping on the last reveal;
/// `-debugGuessFinish YES` jumps to the score.
enum DebugGuess {
    @MainActor static func apply(to model: GuessModel) async {
        guard let count = Int(UserDefaults.standard.string(forKey: "debugGuess") ?? "") else { return }
        model.start()
        let useBest = UserDefaults.standard.bool(forKey: "debugGuessBest")
        for index in 0..<count {
            guard model.phase == .guessing else { break }
            let verdict = model.analysis.verdicts.first { $0.ply == model.ply }
            let uci = index.isMultiple(of: 3) || useBest ? (verdict?.bestMove ?? "") : model.snapshot.moves[model.ply - 1]
            guard model.guess(uci) || model.guess(model.snapshot.moves[model.ply - 1]) else { break }
            for _ in 0..<200 where !model.isRevealed { try? await Task.sleep(for: .milliseconds(20)) }
            if index < count - 1 { model.next() }
        }
        if UserDefaults.standard.bool(forKey: "debugGuessFinish") { model.finish() }
    }
}
#endif
