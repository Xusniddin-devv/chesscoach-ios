import SwiftUI
import SwiftData
import ChessCore

/// The lesson player on the same `TrainingFrame` as the puzzle solver: one progress segment
/// per move to play, the coach narrating each step in successive bubbles, the board edge to
/// edge, and — for scripted lines — "Which move?" answer pills with real moves under the
/// board (the board accepts the move too). The verdict is the same sliding band: accent
/// "Correct" with the step's note, red "Not this one" naming the move, "Lesson complete".
struct LessonView: View {
    let lesson: Lesson
    /// Opens another lesson (Next lesson); nil when this is the last one of its track.
    let onNext: ((Lesson) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.dismiss) private var dismiss
    @State private var model: LessonModel?
    @State private var showPaywall = false
    /// The band after a scripted move: the step's note (right) or the right move (wrong).
    @State private var feedback: Feedback?

    private enum Feedback: Equatable {
        case correct(note: String, step: Int)
        case wrong(answer: String, step: Int)
    }

    private var nextLesson: Lesson? {
        let track = LessonLibrary.lessons(in: lesson.track)
        guard let i = track.firstIndex(where: { $0.id == lesson.id }), i + 1 < track.count else { return nil }
        return track[i + 1]
    }

    var body: some View {
        Group {
            if let model { frame(model) } else { DS.Color.background.ignoresSafeArea() }
        }
        .paywall(isPresented: $showPaywall, feature: .allLessons)
        .holdsEngine()
        .task {
            guard model == nil else { return }
            let next = LessonModel(lesson: lesson)
            next.attach(context)
            model = next
            next.start()
            #if DEBUG
            // `-debugLessonPlay N`: plays the first N scripted moves; `-debugLessonBand 0`
            // dismisses the last band so the next question shows (screenshots).
            let n = UserDefaults.standard.integer(forKey: "debugLessonPlay")
            for i in 0..<n {
                try? await Task.sleep(for: .seconds(1.2))
                guard let move = next.player.expectedMove else { break }
                submit(move, next)
                if i < n - 1 || UserDefaults.standard.string(forKey: "debugLessonBand") == "0" {
                    try? await Task.sleep(for: .seconds(0.8))
                    feedback = nil
                }
            }
            if UserDefaults.standard.string(forKey: "debugLessonWrong") != nil, let q = LessonQuestion.next(for: next.player),
               let wrong = q.answers.first(where: { $0.uci != q.correct.uci }) {
                try? await Task.sleep(for: .seconds(1.2))
                submit(wrong.uci, next)
            }
            #endif
        }
    }

    private func frame(_ model: LessonModel) -> some View {
        let question = feedback == nil ? LessonQuestion.next(for: model.player) : nil
        return TrainingFrame(
            segments: segments(model),
            pose: pose(model),
            lines: lines(model, question: question),
            band: band(model),
            onClose: { dismiss() },
            hintEnabled: model.interactive && feedback == nil,
            onHint: { withAnimation(.snappy) { model.hint() } },
            bottomTitle: "Continue",
            bottomEnabled: false,
            onBottom: {},
            board: {
                BoardView(
                    tracker: model.tracker,
                    fen: model.player.fen,
                    orientation: lesson.userColor,
                    interactive: model.interactive && feedback == nil,
                    lastMove: model.lastMove,
                    squareTint: model.squareTint,
                    badges: [:],
                    arrows: model.arrows,
                    onMove: { uci in submit(uci, model) })
            },
            answers: {
                // Room is kept for the pills so the board never moves between steps.
                AnswerPills(answers: question?.answers ?? [], enabled: question != nil && model.interactive) { uci in
                    submit(uci, model)
                }
                .frame(height: 52)
                .opacity(lesson.goal == .line ? 1 : 0)
            })
        .animation(.snappy(duration: 0.25), value: model.player.status)
    }

    /// Submits a move from the board or a pill and sets the band.
    @discardableResult
    private func submit(_ uci: String, _ model: LessonModel) -> Bool {
        let question = LessonQuestion.next(for: model.player)
        let step = model.player.userMovesDone
        let accepted = model.move(uci)
        guard model.player.isScripted, model.player.status != .completed else { return accepted }
        if accepted, let question {
            feedback = .correct(note: question.note, step: step)
        } else if !accepted, model.wrongMove, let question {
            feedback = .wrong(answer: question.correct.san, step: step)
        }
        return accepted
    }

    // MARK: State → words

    private func segments(_ model: LessonModel) -> [ProgressSegment] {
        guard lesson.goal == .line else {
            return [model.player.status == .completed ? .done : .current]
        }
        let done = model.player.userMovesDone
        return (0..<model.player.userMovesTotal).map { $0 < done ? .done : $0 == done ? .current : .open }
    }

    private func pose(_ model: LessonModel) -> CoachPose {
        switch model.player.status {
        case .completed: return .pleased
        case .failed: return .concerned
        default:
            if case .wrong = feedback { return .concerned }
            if case .correct = feedback { return .pleased }
            return model.thinking ? .thinking : .neutral
        }
    }

    private func lines(_ model: LessonModel, question: LessonQuestion?) -> [String] {
        let side = lesson.userColor == .white ? "White" : "Black"
        var lines = [CoachText.marked(lesson.summary)]
        if model.player.userMovesDone > 0, !model.player.explanation.isEmpty, model.player.explanation != lesson.summary {
            lines.append(CoachText.marked(model.player.explanation))
        }
        switch model.player.status {
        case .completed:
            lines.append(completeLine)
        case .failed(let reason):
            lines.append(CoachText.marked(reason) + " Try it again.")
        case .autoTurn:
            lines.append(lesson.userColor == .white ? "Black answers…" : "White answers…")
        case .opponentTurn:
            lines.append("My move. Let me think.")
        case .userTurn:
            if let question {
                lines.append(question.prompt)
            } else if feedback == nil {
                switch lesson.goal {
                case .mate: lines.append("\(side) to move. **Mate in one.**")
                case .win: lines.append("You have \(side). **Checkmate me.** I'll defend as well as I can.")
                case .draw: lines.append("You have \(side). **Hold the draw.**")
                case .line: break
                }
            }
        }
        if model.engineFailed { lines.append("The engine stopped. Close and open the lesson again.") }
        return lines
    }

    private var completeLine: String {
        switch lesson.goal {
        case .line: "**You played the whole line.** Use it in your next game."
        case .mate: CoachText.marked(lesson.summary)
        case .win: "**Checkmate.** That technique wins every time."
        case .draw: "**Draw held.** Knowing when it's a draw saves half points."
        }
    }

    // MARK: Band

    private func band(_ model: LessonModel) -> TrainingBand? {
        if model.player.status == .completed {
            return TrainingBand(id: "complete", kind: .success, title: "Lesson complete",
                                detail: lesson.goal == .line ? "\(model.player.userMovesTotal) of \(model.player.userMovesTotal) moves, all yours." : nil,
                                primary: nextTitle, onPrimary: next,
                                secondary: "Again", onSecondary: { withAnimation(.snappy) { feedback = nil; model.restart() } })
        }
        if case .failed = model.player.status {
            return TrainingBand(id: "failed", kind: .failure, title: "Not this time",
                                primary: "Try again", onPrimary: { withAnimation(.snappy) { model.restart() } })
        }
        switch feedback {
        case .correct(_, let step):
            // The step's note is already in the coach's bubble; the band says so and moves on.
            return TrainingBand(id: "correct-\(step)", kind: .success, title: "Correct",
                                primary: "Continue", onPrimary: { withAnimation(.snappy) { feedback = nil } })
        case .wrong(let answer, let step):
            return TrainingBand(id: "wrong-\(step)", kind: .failure, title: "Not this one",
                                detail: "[\(answer)] is the move here.",
                                primary: "Try again", onPrimary: { withAnimation(.snappy) { feedback = nil } })
        case nil:
            return nil
        }
    }

    private var nextTitle: String {
        guard let next = nextLesson else { return "Done" }
        return LessonAllowance.isLocked(next, isPro: entitlements.isPro) ? "Next with Pro" : "Next lesson"
    }

    private func next() {
        guard let next = nextLesson else { dismiss(); return }
        if LessonAllowance.isLocked(next, isPro: entitlements.isPro) { showPaywall = true } else if let onNext { onNext(next) } else { dismiss() }
    }
}
