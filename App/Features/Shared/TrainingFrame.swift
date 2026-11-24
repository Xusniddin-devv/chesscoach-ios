import SwiftUI
import ChessCore

// The puzzle solver and the lesson player share one frame: Duolingo's structure (X and a
// thick progress bar, the coach speaking above the board, one chunky button at the bottom,
// the verdict as a full-width band sliding up) told in our coach's voice (Chessigma's
// narrator, square chips in the text, "Which move?" answers). Dark tokens; the band is the
// only large colour on screen (accent when right, blunder red when wrong).

// MARK: Frame

/// One segment of the top progress bar.
enum ProgressSegment: Equatable {
    case open, current, done, missed
}

/// The verdict band: full width, sliding up over the bottom row.
struct TrainingBand {
    enum Kind { case success, failure }

    let id: String
    let kind: Kind
    let title: String
    var detail: String? = nil
    let primary: String
    let onPrimary: () -> Void
    var secondary: String? = nil
    var onSecondary: (() -> Void)? = nil
}

struct TrainingFrame<Board: View, Answers: View>: View {
    let segments: [ProgressSegment]
    var figure: String? = nil
    var figureLabel: String? = nil
    let pose: CoachPose
    /// The coach's narration, oldest first; the last line is the current one.
    let lines: [String]
    let band: TrainingBand?
    let onClose: () -> Void
    let hintEnabled: Bool
    let onHint: () -> Void
    let bottomTitle: String
    let bottomEnabled: Bool
    let onBottom: () -> Void
    @ViewBuilder let board: Board
    @ViewBuilder let answers: Answers
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            topRow
            Narration(pose: pose, lines: lines)
                .padding(.horizontal, DS.Spacing.m)
                .padding(.top, DS.Spacing.xs)
            Spacer(minLength: DS.Spacing.s)
            board
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
            if band == nil {
                // Answers give their room to the band, so the board never has to shrink.
                answers
                    .padding(.horizontal, DS.Spacing.m)
                    .padding(.top, DS.Spacing.sm)
                    .transition(.opacity)
            }
            Spacer(minLength: DS.Spacing.s)
            // The band takes the bottom row's place and counts in the layout, so it never
            // covers the board: the spacers give way and the board moves up a little.
            ZStack(alignment: .bottom) {
                bottomRow
                    .opacity(band == nil ? 1 : 0)
                if let band {
                    BandView(band: band)
                        .id(band.id)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(DS.Color.background.ignoresSafeArea())
        .animation(.spring(duration: 0.38, bounce: 0.15), value: band?.id)
        .sensoryFeedback(trigger: band?.id) { _, new in
            guard new != nil, let band else { return nil }
            return band.kind == .success ? .success : .error
        }
    }

    private var topRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button(action: onClose) {
                IconImage("close", size: 20)
                    .foregroundStyle(DS.Color.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            SegmentedProgressBar(segments: segments)
            if let figure {
                Text(verbatim: figure)
                    .font(.system(.headline, design: .monospaced, weight: .semibold))
                    .foregroundStyle(DS.Color.text)
                    .accessibilityLabel(figureLabel ?? figure)
            }
        }
        .padding(.leading, DS.Spacing.xs)
        .padding(.trailing, DS.Spacing.m)
        .frame(height: 52)
    }

    private var bottomRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            ChunkyIconButton(icon: "hint", label: "Hint", action: onHint)
                .disabled(!hintEnabled)
            Button(bottomTitle, action: onBottom)
                .buttonStyle(ChunkyButtonStyle())
                .disabled(!bottomEnabled)
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.bottom, DS.Spacing.s)
    }
}

// MARK: Narration

/// The coach on the left, the current line in a speech bubble pointing at it; the line
/// before stays above it, smaller and dimmed, so the session reads as a story.
private struct Narration: View {
    let pose: CoachPose
    let lines: [String]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            CoachAvatar(pose: pose, size: 84)
                .id(pose)
                .transition(.opacity)
                .padding(.leading, -10)
            VStack(alignment: .leading, spacing: 6) {
                // The line before stays only while the current one is short enough for both.
                if lines.count > 1, let previous = lines.dropLast().last, (lines.last?.count ?? 0) < 44 {
                    CoachText(previous)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(2)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Color.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .id("prev-\(previous)")
                        .transition(.opacity)
                }
                if let current = lines.last {
                    CoachText(current)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DS.Color.text)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, DS.Spacing.m)
                        .padding(.vertical, DS.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(BubbleShape(tailY: 20).fill(DS.Color.surface))
                        .id(current)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.94, anchor: .bottomLeading).combined(with: .opacity),
                            removal: .opacity))
                }
            }
            .padding(.bottom, 16)
        }
        .frame(height: 136, alignment: .bottom)
        .animation(.spring(duration: 0.35, bounce: 0.25), value: lines)
        .animation(.easeInOut(duration: 0.2), value: pose)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach: \(lines.last.map(CoachText.plain) ?? "")")
    }
}

// MARK: Band

private struct BandView: View {
    let band: TrainingBand

    private var face: Color { band.kind == .success ? DS.Color.accent : DS.Color.danger }
    private var edge: Color { band.kind == .success ? DS.Color.accentPressed : Self.dangerEdge }
    static let dangerEdge = Color(hex: 0xC4212C)

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: 10) {
                IconImage(band.kind == .success ? "check" : "close", size: 16)
                    .foregroundStyle(face)
                    .frame(width: 30, height: 30)
                    .background(.white, in: Circle())
                Text(band.title)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let detail = band.detail {
                CoachText(detail)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if let secondary = band.secondary, let onSecondary = band.onSecondary {
                    Button(secondary, action: onSecondary)
                        .buttonStyle(ChunkyButtonStyle(face: edge, edge: edge.opacity(0.6), label: .white))
                }
                Button(band.primary, action: band.onPrimary)
                    .buttonStyle(ChunkyButtonStyle(face: .white, edge: Color(hex: 0xC9CDCF), label: face))
            }
            .padding(.top, DS.Spacing.xs)
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.top, 20)
        .padding(.bottom, DS.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous)
                .fill(face)
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: Controls

/// A chunky pressed button: a solid face over a darker edge the face sinks into when pressed.
struct ChunkyButtonStyle: ButtonStyle {
    var face: Color = DS.Color.accent
    var edge: Color = DS.Color.accentPressed
    var label: Color = DS.Color.onAccent
    var height: CGFloat = 52
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(size: 17, weight: .heavy))
            .foregroundStyle(isEnabled ? label : DS.Color.textSecondary.opacity(0.7))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(isEnabled ? face : DS.Color.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isEnabled ? edge : DS.Color.surface)
                    .offset(y: pressed ? 0 : 4)
            }
            .offset(y: pressed ? 4 : 0)
            .padding(.bottom, 4)
            .animation(.snappy(duration: 0.12), value: pressed)
    }
}

/// A square chunky icon button (the hint, left of the main button).
struct ChunkyIconButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            IconImage(icon, size: 22)
        }
        .buttonStyle(ChunkyButtonStyle(face: DS.Color.surface2, edge: Color(hex: 0x1A1D1F), label: DS.Color.text))
        .frame(width: 56)
        .accessibilityLabel(label)
    }
}

/// Thick rounded bar in segments (one per puzzle / lesson move), filling in accent.
struct SegmentedProgressBar: View {
    let segments: [ProgressSegment]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                Capsule()
                    .fill(fill(segment))
                    .overlay(alignment: .top) {
                        if segment == .done {
                            Capsule().fill(.white.opacity(0.28)).frame(height: 3)
                                .padding(.horizontal, 6).padding(.top, 3)
                        }
                    }
                    .overlay {
                        if segment == .current { Capsule().strokeBorder(DS.Color.accent.opacity(0.7), lineWidth: 2) }
                    }
            }
        }
        .frame(height: 14)
        .frame(maxWidth: .infinity)
        .animation(.spring(duration: 0.4, bounce: 0.3), value: segments)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(segments.filter { $0 == .done || $0 == .missed }.count) of \(segments.count)")
    }

    private func fill(_ segment: ProgressSegment) -> Color {
        switch segment {
        case .done: DS.Color.accent
        case .missed: DS.Color.danger.opacity(0.75)
        case .current, .open: DS.Color.surface2
        }
    }
}

/// "Which move?" answers: chunky pills with the piece's Icons8 glyph and the move in SAN.
struct AnswerPills: View {
    let answers: [LessonQuestion.Answer]
    let enabled: Bool
    let onPick: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(answers, id: \.uci) { answer in
                Button { onPick(answer.uci) } label: {
                    HStack(spacing: 6) {
                        IconImage("piece-\(answer.piece)", size: 26)  // large enough to tell a bishop's mitre from a pawn
                        Text(verbatim: answer.san)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                    }
                }
                .buttonStyle(ChunkyButtonStyle(face: DS.Color.surface2, edge: Color(hex: 0x1A1D1F), label: DS.Color.text, height: 48))
                .accessibilityLabel("Play \(answer.san)")
            }
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

// MARK: Lesson questions

/// The lesson's next scripted user move as a question with real answers: the right move and
/// one or two plausible wrong ones (other moves of the same piece first).
struct LessonQuestion: Equatable {
    struct Answer: Equatable {
        let uci: String
        let san: String
        /// Icons8 piece glyph name (`piece-knight` …).
        let piece: String
    }

    let correct: Answer
    let answers: [Answer]
    let prompt: String
    /// The step's note, said once the move is played.
    let note: String

    static func next(for player: LessonPlayer) -> LessonQuestion? {
        guard player.lesson.goal == .line, player.status == .userTurn, let uci = player.expectedMove,
              let correct = answer(uci, fen: player.fen) else { return nil }
        let userSteps = player.lesson.steps.filter { $0.side == .user }
        let note = userSteps.indices.contains(player.userMovesDone) ? userSteps[player.userMovesDone].explanation : ""
        let kind = Rules.piece(at: Square(String(uci.prefix(2))), fen: player.fen)?.kind
        let others = Rules.legalMoves(fen: player.fen).filter { $0 != uci }
            .compactMap { answer($0, fen: player.fen) }
            .sorted { $0.san < $1.san }
        // Plausible wrong answers: another move of the same piece, then developing moves
        // (minor pieces, then pawns), never the king or a capture.
        func rank(_ a: Answer) -> Int {
            let k = Rules.piece(at: Square(String(a.uci.prefix(2))), fen: player.fen)?.kind
            if k == kind { return 0 }
            switch k {
            case .knight?, .bishop?: return 1
            case .pawn?: return 2
            case .rook?, .queen?: return 3
            default: return 9
            }
        }
        let candidates = others.filter { !$0.san.contains("x") && rank($0) < 9 }
            .sorted { (rank($0), $0.san) < (rank($1), $1.san) }
        var wrong: [Answer] = []
        for c in candidates where wrong.count < 2 && !wrong.contains(where: { $0.piece == c.piece && rank(c) > 0 }) {
            wrong.append(c)
        }
        // A stable order that doesn't always put the right move first.
        var all = [correct] + wrong
        let turn = uci.unicodeScalars.reduce(0) { $0 + Int($1.value) } % all.count
        all = Array(all[turn...] + all[..<turn])
        let prompt = note.isEmpty ? "**Which move?** Continue the line." : "**Which move?** " + note
        return LessonQuestion(correct: correct, answers: all, prompt: CoachText.marked(prompt),
                              note: CoachText.marked(note))
    }

    private static func answer(_ uci: String, fen: String) -> Answer? {
        guard let applied = Rules.apply(uci: uci, to: fen),
              let piece = Rules.piece(at: Square(String(uci.prefix(2))), fen: fen) else { return nil }
        return Answer(uci: uci, san: applied.san, piece: glyph(piece.kind))
    }

    static func glyph(_ kind: Piece.Kind) -> String {
        switch kind {
        case .king: "king"
        case .queen: "queen"
        case .rook: "rook"
        case .bishop: "bishop"
        case .knight: "knight"
        case .pawn: "pawn"
        }
    }
}
