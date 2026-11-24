import SwiftUI
import SwiftData
import ChessCore

/// Full-screen lesson on Play's layout (`TrainingBoardScaffold`), like the puzzle solver:
/// a flat top row (close, one pip per move to play, lesson title, "3 / 7" in mono), the
/// prompt with the side to move, the board centred, the status line, the coach explaining
/// each step in a speech bubble (square chips, moves in bold), and the flat action bar
/// Hint · Start over · Next (accent once the lesson is complete). No stacked cards.
struct LessonView: View {
    let lesson: Lesson
    /// Opens another lesson (Next lesson); nil when this is the last one of its track.
    let onNext: ((Lesson) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.dismiss) private var dismiss
    @State private var model: LessonModel?
    @State private var showPaywall = false

    private var nextLesson: Lesson? {
        let track = LessonLibrary.lessons(in: lesson.track)
        guard let i = track.firstIndex(where: { $0.id == lesson.id }), i + 1 < track.count else { return nil }
        return track[i + 1]
    }

    var body: some View {
        Group {
            if let model { content(model) } else { DS.Color.background }
        }
        .background(DS.Color.background.ignoresSafeArea())
        .paywall(isPresented: $showPaywall, feature: .allLessons)
        .task {
            guard model == nil else { return }
            let next = LessonModel(lesson: lesson)
            next.attach(context)
            model = next
            next.start()
            #if DEBUG
            // `-debugLessonPlay N`: plays the first N scripted moves (screenshots).
            let n = UserDefaults.standard.integer(forKey: "debugLessonPlay")
            for _ in 0..<n {
                try? await Task.sleep(for: .seconds(1.2))
                guard let move = next.player.expectedMove else { break }
                _ = next.move(move)
            }
            #endif
        }
    }

    private func content(_ model: LessonModel) -> some View {
        TrainingBoardScaffold(
            prompt: prompt(model),
            side: lesson.userColor,
            status: status(model),
            statusAccessory: model.engineFailed ? .action("Retry", model.retryEngine) : nil,
            header: {
                TrainingTopBar(
                    pips: pips(model), current: lesson.goal == .line ? model.player.userMovesDone : nil,
                    title: lesson.title,
                    figure: lesson.goal == .line ? "\(model.player.userMovesDone) / \(model.player.userMovesTotal)" : nil,
                    figureLabel: "\(model.player.userMovesDone) of \(model.player.userMovesTotal) moves") { dismiss() }
            },
            board: {
                BoardView(
                    tracker: model.tracker,
                    fen: model.player.fen,
                    orientation: lesson.userColor,
                    interactive: model.interactive,
                    lastMove: model.lastMove,
                    squareTint: model.squareTint,
                    badges: [:],
                    arrows: model.arrows,
                    onMove: model.move)
            },
            coach: { coach(model) },
            actions: { actionBar(model) })
        .animation(.snappy(duration: 0.25), value: model.player.status)
        .animation(.snappy(duration: 0.2), value: model.wrongMove)
    }

    // MARK: Words

    /// Scripted lines: one pip per move to play, done ones filled.
    private func pips(_ model: LessonModel) -> [Bool?] {
        guard lesson.goal == .line else { return [] }
        return (0..<model.player.userMovesTotal).map { $0 < model.player.userMovesDone ? true : nil }
    }

    private func prompt(_ model: LessonModel) -> String {
        let side = lesson.userColor == .white ? "White" : "Black"
        switch lesson.goal {
        case .line: return "You play \(side) · \(lesson.track.title.lowercased().dropLast()) line"
        case .mate: return "\(side) to move · mate in one"
        case .win: return "\(side) to move · checkmate"
        case .draw: return "\(side) to move · hold the draw"
        }
    }

    private func status(_ model: LessonModel) -> String? {
        if model.engineFailed { return "The engine stopped" }
        switch model.player.status {
        case .completed: return "Lesson complete"
        case .failed: return "Not this time"
        case .autoTurn: return lesson.userColor == .white ? "Black replies…" : "White replies…"
        case .opponentTurn: return "Engine is thinking…"
        case .userTurn:
            if model.wrongMove {
                return model.player.hintLevel >= 2 ? "Not this one · the arrow shows the move" : "Not this one · the piece to move is marked"
            }
            return "Your move"
        }
    }

    @ViewBuilder
    private func coach(_ model: LessonModel) -> some View {
        switch model.player.status {
        case .completed:
            CoachBubble(pose: .pleased, text: CoachText.marked(completeMessage), avatarSize: 52)
        case .failed(let reason):
            CoachBubble(pose: .concerned, text: CoachText.marked(reason), avatarSize: 52)
        default:
            CoachBubble(pose: model.wrongMove ? .thinking : .neutral,
                        text: CoachText.marked(model.player.explanation), avatarSize: 52)
        }
    }

    private var completeMessage: String {
        switch lesson.goal {
        case .line: "**You played the whole line.** Use it in your next game."
        case .mate: lesson.summary
        case .win: "**Checkmate.** That technique wins every time."
        case .draw: "**Draw held.** Knowing when it's a draw saves half points."
        }
    }

    // MARK: Action bar

    private func actionBar(_ model: LessonModel) -> some View {
        let complete = model.player.status == .completed
        return GameActionBar {
            GameAction(title: "Hint", icon: "hint") { model.hint() }
                .disabled(!model.interactive)
            GameAction(title: "Start over", icon: "return") { withAnimation(.snappy) { model.restart() } }
            if let next = nextLesson, LessonAllowance.isLocked(next, isPro: entitlements.isPro) {
                GameAction(title: "Next", icon: "lock", prominent: complete) { showPaywall = true }
                    .accessibilityLabel("Next lesson with Pro")
            } else if let next = nextLesson, let onNext {
                GameAction(title: "Next", icon: "forward", prominent: complete) { onNext(next) }
                    .accessibilityLabel("Next lesson")
            } else {
                GameAction(title: "Done", icon: "forward", prominent: complete) { dismiss() }
            }
        }
    }
}
