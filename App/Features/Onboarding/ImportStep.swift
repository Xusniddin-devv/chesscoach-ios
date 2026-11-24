import SwiftUI
import ChessCore

/// The live import, about ten seconds once the games are in. A chunky bar counts the games
/// read; the coach reacts to each one; one big board replays the real key moment of the game
/// he just read (the mistake drawn as an arrow, then played); a row of 20 result tokens fills
/// in (accuracy only when it is real). Once a few games are read the coach asks one quick
/// question with reply chips, and when enough is known he hands over while the rest is read
/// in the background.
struct ImportStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.s) {
                BarButton(systemImage: "xmark", label: "Cancel import", action: model.cancelImport)
                ChunkyProgress(value: progress)
                    .padding(.trailing, DS.Spacing.m)
            }
            .frame(height: 44)
            .padding(.leading, DS.Spacing.s)

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.m) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Reading your last \(OnboardingModel.gameLimit)")
                            .foregroundStyle(DS.Color.textSecondary)
                        Spacer()
                        Text(progressLabel)
                            .foregroundStyle(DS.Color.text)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: progressLabel)
                    }
                    .font(DS.Font.subheadline.weight(.semibold).monospacedDigit())

                    CoachBubble(model.coachLine, avatarSize: 68)
                        .frame(minHeight: 84, alignment: .bottom)

                    KeyMomentBoard(model: model)

                    ResultTokens(model: model)
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.m)
            }
            .scrollBounceBehavior(.basedOnSize)

            // The bottom dock: the coach's one question once a few games are read.
            Group {
                if model.askingFrequency {
                    FrequencyQuestion(model: model)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if model.phase != .fetching, !isFailed {
                    Text("\(model.positionsRead.formatted()) positions read · Powered by Stockfish")
                        .font(DS.Font.caption.monospacedDigit())
                        .foregroundStyle(DS.Color.textSecondary)
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.bottom, DS.Spacing.s)
            .animation(.snappy(duration: 0.35), value: model.askingFrequency)

            if case .failed(let message) = model.phase {
                VStack(spacing: DS.Spacing.s) {
                    Text(message)
                        .font(DS.Font.subheadline)
                        .foregroundStyle(DS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                    PrimaryButton(title: "Try again", action: model.retryImport)
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.s)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.gamesAnalysed)
    }

    private var isFailed: Bool { if case .failed = model.phase { true } else { false } }

    private var progress: Double {
        guard model.fetchedCount > 0 else { return 0 }
        return Double(model.gamesAnalysed) / Double(model.fetchedCount)
    }

    private var progressLabel: String {
        let total = model.fetchedCount
        switch model.phase {
        case .fetching: return total == 0 ? "Asking \(model.platform?.title ?? "")" : "Fetching \(total) of \(OnboardingModel.gameLimit)"
        case .reading: return "Game \(min(model.gamesAnalysed + 1, total)) of \(total)"
        case .done: return model.gamesAnalysed >= total ? "All \(total) read" : "\(model.gamesAnalysed) of \(total) read"
        case .failed: return "Stopped"
        }
    }
}

/// A thick rounded bar: accent fill with a lighter strip along its top, like a tube.
struct ChunkyProgress: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            let w = max(0, min(1, value)) * geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(DS.Color.surface2)
                Capsule()
                    .fill(DS.Color.accent)
                    .frame(width: value > 0 ? max(geo.size.height, w) : 0)
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(.white.opacity(0.28))
                            .frame(height: 3)
                            .padding(.horizontal, geo.size.height / 2)
                            .padding(.top, 3)
                    }
            }
        }
        .frame(height: 16)
        .animation(.spring(duration: 0.5, bounce: 0.25), value: value)
        .accessibilityElement()
        .accessibilityLabel("Games read")
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}

// MARK: - Key moment

/// The game the coach just read, big. Its worst move is drawn as an arrow on the position
/// before it, then played, with its grade on the square. Before any game is read, the sweep's
/// game flips through to its final position.
private struct KeyMomentBoard: View {
    let model: OnboardingModel
    @State private var played = false

    private var slot: OnboardingModel.Slot? {
        if let id = model.finishOrder.last { return model.slots[id] }
        return model.sweepSlot
    }

    var body: some View {
        let slot = slot
        let moment = slot.flatMap { $0.analysed ? model.keyMoment($0) : nil }
        let orientation = slot?.snapshot?.userColor ?? .white
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            ZStack {
                if let slot, let moment {
                    MiniBoard(fen: played ? moment.facts.fenAfter : moment.facts.fenBefore, orientation: orientation)
                    if played {
                        MoveMark(uci: moment.uci, orientation: orientation, moveClass: moment.classification)
                            .transition(.opacity)
                    } else {
                        MoveArrow(uci: moment.uci, orientation: orientation, color: DS.Color.moveClass(moment.classification))
                            .transition(.opacity)
                    }
                    Color.clear.task(id: "\(slot.id)-\(moment.ply)") {
                        played = false
                        try? await Task.sleep(for: .milliseconds(900))
                        withAnimation(.easeInOut(duration: 0.25)) { played = true }
                    }
                } else if let slot {
                    let fens = slot.fens
                    MiniBoard(fen: fens.isEmpty ? Rules.startFen : fens[min(slot.analysed ? fens.count - 1 : model.sweepPly, fens.count - 1)],
                              orientation: orientation)
                } else {
                    MiniBoard(fen: Rules.startFen)
                        .opacity(0.25)
                        .overlay { ProgressView().tint(DS.Color.text) }
                }
            }
            .frame(maxWidth: 300)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.25), value: played)

            Text(caption(slot, moment))
                .font(DS.Font.caption.monospacedDigit())
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    private func caption(_ slot: OnboardingModel.Slot?, _ moment: Verdict?) -> String {
        guard let slot, let s = slot.snapshot else { return "Fetching your games" }
        var parts = ["Game \(slot.id + 1)"]
        if let opp = s.opponentName { parts.append("vs \(opp)") }
        if let moment {
            parts.append("move \(moment.facts.moveNumber)")
            parts.append(moment.classification.rawValue.capitalized)
        } else if slot.analysed {
            parts.append("no big mistakes")
        } else {
            parts.append(slot.won.map { $0 ? "won" : "lost" } ?? "draw")
        }
        return parts.joined(separator: " · ")
    }
}

/// An arrow from the move's origin to its destination, drawn over a board.
struct MoveArrow: View {
    let uci: String
    let orientation: Piece.Color
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            if uci.count >= 4 {
                let from = BoardGeometry.rect(for: Square(String(uci.prefix(2))), orientation: orientation, side: side)
                let to = BoardGeometry.rect(for: Square(String(uci.dropFirst(2).prefix(2))), orientation: orientation, side: side)
                let cell = from.width
                let a = CGPoint(x: from.midX, y: from.midY), b = CGPoint(x: to.midX, y: to.midY)
                let angle = atan2(b.y - a.y, b.x - a.x)
                let head = cell * 0.42
                let shaftEnd = CGPoint(x: b.x - cos(angle) * head * 0.8, y: b.y - sin(angle) * head * 0.8)
                ZStack {
                    Path { p in p.move(to: a); p.addLine(to: shaftEnd) }
                        .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: cell * 0.2, lineCap: .round))
                    Path { p in
                        p.move(to: b)
                        p.addLine(to: CGPoint(x: b.x - cos(angle - .pi / 6) * head, y: b.y - sin(angle - .pi / 6) * head))
                        p.addLine(to: CGPoint(x: b.x - cos(angle + .pi / 6) * head, y: b.y - sin(angle + .pi / 6) * head))
                        p.closeSubpath()
                    }
                    .fill(color.opacity(0.9))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Result tokens

/// Twenty small tokens, one per game: W / L / D once the sweep has passed it, the accuracy
/// under the letter once it is real; the one being looked at ringed.
private struct ResultTokens: View {
    let model: OnboardingModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 10)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(model.slots) { slot in
                Token(slot: slot, revealed: revealed(slot), current: isCurrent(slot))
            }
        }
    }

    private func revealed(_ slot: OnboardingModel.Slot) -> Bool {
        guard slot.state == .fetched else { return false }
        if slot.analysed || model.sweepDone { return true }
        guard let at = model.sweepIndex else { return false }
        return slot.id <= at
    }

    private func isCurrent(_ slot: OnboardingModel.Slot) -> Bool {
        if let last = model.finishOrder.last { return last == slot.id && model.phase == .reading }
        return model.sweepIndex == slot.id
    }
}

private struct Token: View {
    let slot: OnboardingModel.Slot
    let revealed: Bool
    let current: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7)
        ZStack {
            Color.clear
            VStack(spacing: 0) {
            if revealed {
                Text(letter)
                    .font(.subheadline.weight(.heavy))
                    .fontDesign(.rounded)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(letterColor)
                if let a = slot.accuracy {
                    Text(String(Int(a.rounded())))
                        .font(.caption2.weight(.semibold).monospaced())
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(DS.Color.textSecondary)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(0.82, contentMode: .fit)
        .background {
            if slot.state == .waiting || (slot.state == .fetched && !revealed) {
                shape.strokeBorder(DS.Color.surface2, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            } else if slot.state == .failed {
                shape.fill(DS.Color.surface.opacity(0.4))
            } else {
                shape.fill(fill)
            }
        }
        .overlay { if current { shape.strokeBorder(DS.Color.accent, lineWidth: 2) } }
        .scaleEffect(current ? 1.1 : 1)
        .animation(.spring(duration: 0.3, bounce: 0.3), value: revealed)
        .animation(.spring(duration: 0.3), value: current)
        .animation(.snappy, value: slot.accuracy)
        .accessibilityElement()
        .accessibilityLabel(accessibility)
    }

    private var letter: String {
        switch slot.won {
        case true: "W"
        case false: "L"
        default: "D"
        }
    }

    private var fill: Color { DS.Color.surface }

    private var letterColor: Color {
        switch slot.won {
        case true: DS.Color.accent
        case false: DS.Color.text.opacity(0.75)
        default: DS.Color.boardLight
        }
    }

    private var accessibility: String {
        guard revealed else { return slot.state == .failed ? "No game" : "Not read yet" }
        let word = slot.won.map { $0 ? "Won" : "Lost" } ?? "Draw"
        return slot.accuracy.map { "\(word), accuracy \(Int($0))" } ?? word
    }
}

// MARK: - The coach's question

/// "How often do you play?" with reply chips, asked while the rest is read. The answer sizes
/// the week; the chosen chip stays as the user's reply.
private struct FrequencyQuestion: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(alignment: .bottom, spacing: DS.Spacing.s) {
                CoachAvatar(pose: model.frequency == nil ? .neutral : .pleased, size: 44)
                ChatBubble(text: model.frequency == nil
                           ? "Quick one while I read: **how often do you play?**"
                           : "Got it. I'll size your week for that.")
            }
            HStack(spacing: DS.Spacing.s) {
                Spacer(minLength: 0)
                ForEach(PlayFrequency.allCases, id: \.self) { f in
                    if model.frequency == nil || model.frequency == f {
                        QuickReply(title: f.title, selected: model.frequency == f) { model.answerFrequency(f) }
                            .disabled(model.frequency != nil)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: model.frequency)
    }
}
