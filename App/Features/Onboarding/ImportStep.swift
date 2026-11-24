import SwiftUI
import ChessCore

/// The live import: the coach narrates while the user's games arrive as boards, the board
/// being read plays through its moves, and each finished game flips to show how it went.
struct ImportStep: View {
    let model: OnboardingModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.s), count: 5)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                BarButton(systemImage: "xmark", label: "Cancel import", action: model.cancelImport)
                Spacer()
                if model.phase == .analysing, model.gamesDone >= 1 {
                    Button("Skip the rest", action: model.skipRest)
                        .font(DS.Font.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Color.textSecondary)
                        .padding(.horizontal, DS.Spacing.m)
                        .transition(.opacity)
                }
            }
            .frame(height: 44)
            .padding(.horizontal, DS.Spacing.s)
            .animation(.easeInOut, value: model.gamesDone >= 1)

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    CoachBubble(model.coachLine, avatarSize: 84)
                        .frame(minHeight: 112, alignment: .bottom)

                    LiveGame(model: model)

                    LazyVGrid(columns: columns, spacing: DS.Spacing.s) {
                        ForEach(model.slots) { slot in
                            GameTile(slot: slot)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.s)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.gamesDone)
    }

    @ViewBuilder
    private var footer: some View {
        switch model.phase {
        case .done:
            PrimaryButton(title: "See where you stand") { model.go(.reveal) }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        case .failed(let message):
            VStack(spacing: DS.Spacing.s) {
                Text(message)
                    .font(DS.Font.subheadline)
                    .foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                PrimaryButton(title: "Try again", action: model.retryImport)
            }
        default:
            EmptyView()
        }
    }
}

/// The game being read right now, big: its moves play through as Stockfish reaches them.
/// Beside it the count of positions read ticks up.
private struct LiveGame: View {
    let model: OnboardingModel

    var body: some View {
        let slot = model.liveSlot
        HStack(alignment: .top, spacing: DS.Spacing.m) {
            ZStack {
                if let slot {
                    MiniBoard(fen: slot.fen, orientation: slot.snapshot?.userColor ?? .white)
                        .animation(.easeOut(duration: 0.15), value: slot.ply)
                } else {
                    RoundedRectangle(cornerRadius: DS.Radius.small)
                        .fill(DS.Color.surface)
                    if model.phase == .fetching || model.phase == .converting {
                        ProgressView().tint(DS.Color.textSecondary)
                    } else if model.phase == .done {
                        Glyph(name: "play", size: 44).foregroundStyle(DS.Color.textSecondary)
                    }
                }
            }
            .frame(width: 168, height: 168)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(heading)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                Text(title)
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.text)
                    .lineLimit(2)
                if let slot, let snapshot = slot.snapshot {
                    Text("Move \(max(1, (slot.ply + 1) / 2)) of \(max(1, (snapshot.moves.count + 1) / 2))")
                        .font(DS.Font.subheadline.monospacedDigit())
                        .foregroundStyle(DS.Color.textSecondary)
                }
                Spacer(minLength: DS.Spacing.s)
                Text(model.movesAnalysed, format: .number)
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DS.Color.text)
                    .contentTransition(.numericText(value: Double(model.movesAnalysed)))
                    .animation(.snappy(duration: 0.2), value: model.movesAnalysed)
                Text("positions read by Stockfish")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            .frame(height: 168, alignment: .topLeading)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var heading: String {
        switch model.phase {
        case .fetching: model.fetchedCount == 0 ? "Asking \(model.platform?.title ?? "")" : "Fetching"
        case .converting: "Setting up"
        case .analysing: "Game \(min(model.gamesDone + 1, model.games.count)) of \(model.games.count)"
        case .done: "Finished"
        case .failed: "Stopped"
        }
    }

    private var title: String {
        switch model.phase {
        case .fetching: "\(model.fetchedCount) of \(OnboardingModel.gameLimit) games"
        case .converting: "Laying out the boards"
        case .analysing: model.liveSlot?.snapshot?.opponentName.map { "vs \($0)" } ?? "Reading"
        case .done: "\(model.report?.gamesAnalysed ?? 0) games read"
        case .failed: "Import stopped"
        }
    }
}

/// One game: an empty slot, then its board (dim), the board playing through while it is read,
/// then flipped over to the result and the user's accuracy.
private struct GameTile: View {
    let slot: OnboardingModel.Slot

    private var flipped: Bool { slot.state == .done }

    var body: some View {
        ZStack {
            front
                .opacity(flipped ? 0 : 1)
            back
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .aspectRatio(1, contentMode: .fit)
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .scaleEffect(slot.state == .analysing ? 1.06 : 1)
        .zIndex(slot.state == .analysing ? 1 : 0)
        .animation(.spring(duration: 0.35), value: slot.state)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    @ViewBuilder
    private var front: some View {
        switch slot.state {
        case .waiting:
            RoundedRectangle(cornerRadius: DS.Radius.small)
                .strokeBorder(DS.Color.surface2, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        case .fetched, .analysing, .failed:
            MiniBoard(fen: slot.fen, orientation: slot.snapshot?.userColor ?? .white)
                .saturation(slot.state == .analysing ? 1 : 0)
                .opacity(slot.state == .analysing ? 1 : (slot.state == .failed ? 0.08 : 0.2))
                .overlay {
                    if slot.state == .analysing {
                        RoundedRectangle(cornerRadius: DS.Radius.small / 2)
                            .strokeBorder(DS.Color.accent, lineWidth: 2.5)
                    }
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
        case .done:
            Color.clear
        }
    }

    private var back: some View {
        VStack(spacing: 2) {
            Text(resultWord)
                .font(DS.Font.caption.weight(.semibold))
                .foregroundStyle(slot.won == true ? DS.Color.accent : DS.Color.textSecondary)
            Text(slot.accuracy.map { String(Int($0.rounded())) } ?? "–")
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(DS.Color.text)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.small))
    }

    private var resultWord: String {
        switch slot.won {
        case true: "Won"
        case false: "Lost"
        default: "Draw"
        }
    }

    private var accessibility: String {
        switch slot.state {
        case .waiting: "Waiting"
        case .fetched: "Fetched, not read yet"
        case .analysing: "Reading this game"
        case .failed: "Couldn't read this game"
        case .done: "\(resultWord), accuracy \(slot.accuracy.map { String(Int($0)) } ?? "unknown")"
        }
    }
}
