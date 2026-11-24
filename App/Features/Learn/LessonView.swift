import SwiftUI
import SwiftData
import ChessCore

/// Full-screen lesson: board, a progress line, and the explanation card under it.
/// Glass toolbar: close, restart, hint.
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
        NavigationStack {
            Group {
                if let model { content(model) } else { DS.Color.background }
            }
            .background(DS.Color.background)
            .navigationTitle(lesson.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Start over", systemImage: "arrow.counterclockwise") { model?.restart() }
                    Button("Hint", systemImage: "lightbulb") { model?.hint() }
                        .disabled(model?.interactive != true)
                }
            }
        }
        .tint(DS.Color.text)
        .task {
            guard model == nil else { return }
            let next = LessonModel(lesson: lesson)
            next.attach(context)
            model = next
            next.start()
        }
    }

    private func content(_ model: LessonModel) -> some View {
        VStack(spacing: 0) {
            progressLine(model)
                .padding(.horizontal, DS.Spacing.m)
                .padding(.vertical, DS.Spacing.sm)
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
            .padding(.horizontal, DS.Spacing.s)
            ScrollView {
                card(model)
                    .padding(.horizontal, DS.Spacing.m)
                    .padding(.vertical, DS.Spacing.m)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .animation(.snappy(duration: 0.25), value: model.player.status)
    }

    private func progressLine(_ model: LessonModel) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(lesson.track.title)
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
            Spacer()
            if lesson.goal == .line {
                Text("\(model.player.userMovesDone) / \(model.player.userMovesTotal)")
                    .font(DS.Font.numeral)
                    .accessibilityLabel("\(model.player.userMovesDone) of \(model.player.userMovesTotal) moves")
            }
        }
    }

    @ViewBuilder
    private func card(_ model: LessonModel) -> some View {
        switch model.player.status {
        case .completed:
            ResultCard(title: "Lesson complete", message: completeMessage, positive: true) {
                HStack(spacing: DS.Spacing.sm) {
                    SecondaryButton(title: "Again", action: model.restart)
                    if let next = nextLesson, LessonAllowance.isLocked(next, isPro: entitlements.isPro) {
                        PrimaryButton(title: "Next lesson with Pro") { showPaywall = true }
                            .paywall(isPresented: $showPaywall, feature: .allLessons)
                    } else if let next = nextLesson, let onNext {
                        PrimaryButton(title: "Next lesson") { onNext(next) }
                    } else {
                        PrimaryButton(title: "Done") { dismiss() }
                    }
                }
            }
        case .failed(let reason):
            ResultCard(title: "Not this time", message: reason, positive: false) {
                PrimaryButton(title: "Try again", action: model.restart)
            }
        default:
            explanation(model)
        }
    }

    private func explanation(_ model: LessonModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SectionLabel(label(model))
            Text(model.player.explanation)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.text)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            if model.wrongMove {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                    Circle().fill(DS.Color.danger).frame(width: 8, height: 8)
                    Text(model.player.hintLevel >= 2 ? "Not this one. The arrow shows the move." : "Not this one. The piece to move is marked.")
                        .font(DS.Font.subheadline)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                .transition(.opacity)
            }
            if model.engineFailed {
                Button("The engine stopped. Retry") { model.retryEngine() }
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.accent)
            }
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
        .animation(.snappy(duration: 0.2), value: model.wrongMove)
    }

    private func label(_ model: LessonModel) -> String {
        let side = lesson.userColor == .white ? "White" : "Black"
        switch model.player.status {
        case .autoTurn: return lesson.userColor == .white ? "Black replies" : "White replies"
        case .opponentTurn: return "Engine is thinking"
        default: break
        }
        switch lesson.goal {
        case .line: return "Your move as \(side)"
        case .mate: return "Checkmate in one"
        case .win: return "Goal: checkmate"
        case .draw: return "Goal: hold the draw"
        }
    }

    private var completeMessage: String {
        switch lesson.goal {
        case .line: "You played the whole line. Use it in your next game."
        case .mate: lesson.summary
        case .win: "Checkmate. That technique wins every time."
        case .draw: "Draw held. Knowing when it's a draw saves half points."
        }
    }
}
