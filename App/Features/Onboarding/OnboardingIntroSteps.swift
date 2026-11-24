import SwiftUI
import ChessCore

// MARK: Welcome

/// One confident screen: the coach standing on the edge of a board, saying hello.
struct WelcomeStep: View {
    let model: OnboardingModel
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Chess Coach")
                .font(DS.Font.headline)
                .foregroundStyle(DS.Color.text)
                .padding(.top, DS.Spacing.sm)
                .padding(.horizontal, DS.Spacing.m)

            Spacer(minLength: DS.Spacing.l)

            VStack(spacing: 0) {
                CoachBubble(pose: appeared ? .pleased : .neutral,
                            text: "Hi, I'm your coach. Show me your games and I'll tell you what keeps costing you.",
                            avatarSize: 200, animated: false, grounded: true)
                    .padding(.horizontal, DS.Spacing.m)
                    .padding(.bottom, -30)
                    .zIndex(1)  // the base stands on the board's edge
                BoardEdge()
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text("Your games,\nread by a coach.")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(DS.Color.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Bring your chess.com or Lichess games. Stockfish 18 reads every move right here on your iPhone.")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.top, DS.Spacing.l)

            Spacer(minLength: DS.Spacing.l)

            PrimaryButton(title: "Get started") { model.go(.platform) }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.s)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.3).delay(0.1)) { appeared = true }
        }
    }
}

/// The near edge of a board in perspective: the floor the coach stands on.
struct BoardEdge: View {
    var ranks = 3

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            // Each rank is taller and wider than the one behind it.
            let topWidth = w * 1.1, bottomWidth = w * 1.6
            let rowHeights: [CGFloat] = (0..<ranks).map { pow(1.45, CGFloat($0)) }
            let total = rowHeights.reduce(0, +)
            var y: CGFloat = 0
            func width(at y: CGFloat) -> CGFloat { topWidth + (bottomWidth - topWidth) * (y / h) }
            for rank in 0..<ranks {
                let rowH = h * rowHeights[rank] / total
                let w0 = width(at: y), w1 = width(at: y + rowH)
                for file in 0..<8 {
                    let x0t = (w - w0) / 2 + w0 * CGFloat(file) / 8, x1t = (w - w0) / 2 + w0 * CGFloat(file + 1) / 8
                    let x0b = (w - w1) / 2 + w1 * CGFloat(file) / 8, x1b = (w - w1) / 2 + w1 * CGFloat(file + 1) / 8
                    var p = Path()
                    p.move(to: CGPoint(x: x0t, y: y)); p.addLine(to: CGPoint(x: x1t, y: y))
                    p.addLine(to: CGPoint(x: x1b, y: y + rowH)); p.addLine(to: CGPoint(x: x0b, y: y + rowH))
                    p.closeSubpath()
                    let light = (file + rank) % 2 == 0
                    context.fill(p, with: .color(light ? DS.Color.boardLight : DS.Color.boardDark))
                }
                y += rowH
            }
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0.55), location: 0.5),
                                     .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        .frame(height: 150)
        .accessibilityHidden(true)
    }
}

// MARK: Platform

struct PlatformStep: View {
    let model: OnboardingModel
    var onClose: (() -> Void)?

    var body: some View {
        OnboardingScaffold(model: model, title: "Where do you play?",
                           subtitle: "I'll read your last 20 games there and build your first week around them.",
                           leading: onClose, leadingSystemImage: "xmark",
                           coach: CoachLine(.neutral, "Either one works. I only read public games, nothing else.")) {
            VStack(spacing: DS.Spacing.sm) {
                ChoiceCard(glyph: "chesscom", title: "chess.com", detail: "Rapid, blitz or daily, whatever you play") {
                    model.choose(.chesscom)
                }
                ChoiceCard(glyph: "lichess", title: "Lichess", detail: "Any time control, standard chess") {
                    model.choose(.lichess)
                }
                ChoiceCard(glyph: "newplayer", title: "I'm new to chess", detail: "Three quick questions instead") {
                    model.choose(nil)
                }
            }
        } footer: { EmptyView() }
    }
}

/// A flat answer card: a glyph on a tile, a title and one line.
struct ChoiceCard<Leading: View>: View {
    @ViewBuilder let leading: Leading
    let title: String
    let detail: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.m) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.Color.text)
                    Text(detail)
                        .font(DS.Font.subheadline)
                        .foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Color.textSecondary)
            }
            .padding(DS.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: DS.Radius.large).strokeBorder(DS.Color.accent, lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.large))
        }
        .buttonStyle(PressScaleStyle())
        .sensoryFeedback(.selection, trigger: selected)
    }
}

extension ChoiceCard where Leading == AnyView {
    init(glyph: String, title: String, detail: String, action: @escaping () -> Void) {
        self.init(leading: {
            AnyView(Glyph(name: glyph, size: 28)
                .foregroundStyle(DS.Color.text)
                .frame(width: 48, height: 48)
                .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: DS.Radius.medium)))
        }, title: title, detail: detail, action: action)
    }
}

/// Slight press-in for tappable cards.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: Username

struct UsernameStep: View {
    @Bindable var model: OnboardingModel
    @FocusState private var focused: Bool

    private var platformTitle: String { model.platform?.title ?? "" }

    private var coachLine: CoachLine {
        switch model.lookup {
        case .idle: CoachLine(.neutral, "Type it as it is on \(platformTitle). Capitals don't matter.")
        case .checking: CoachLine(.thinking, "Looking you up…")
        case .found(let p):
            p.currentRating.map { r in
                RatingTier(rating: r) >= .queen
                    ? CoachLine(.pleased, "Found you. \(r)? I'll take notes quietly.")
                    : CoachLine(.pleased, "Found you. Let's see what your games say.")
            } ?? CoachLine(.pleased, "Found you. Let's see what your games say.")
        case .notFound: CoachLine(.concerned, "Nobody by that name on \(platformTitle). Check the spelling?")
        case .failed: CoachLine(.concerned, "I can't reach \(platformTitle) right now.")
        }
    }

    var body: some View {
        OnboardingScaffold(model: model, title: "Your \(platformTitle) username",
                           subtitle: "Public games only. No password, no sign-in.", coach: coachLine) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    Glyph(name: model.platform == .lichess ? "lichess" : "chesscom", size: 24)
                        .foregroundStyle(DS.Color.textSecondary)
                    TextField("", text: $model.username, prompt: Text("username").foregroundStyle(DS.Color.textSecondary.opacity(0.6)))
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(DS.Color.text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .submitLabel(.go)
                        .focused($focused)
                        .onChange(of: model.username) { model.usernameChanged() }
                        .onSubmit { if model.foundProfile != nil { model.startImport() } }
                }
                .padding(.horizontal, DS.Spacing.m)
                .frame(height: 64)
                .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.large)
                        .strokeBorder(model.foundProfile != nil ? DS.Color.accent : .clear, lineWidth: 2)
                }

                LookupRow(lookup: model.lookup, platform: model.platform, typed: model.username)
                    .animation(.snappy, value: model.lookup)
            }
        } footer: {
            PrimaryButton(title: "Read my games") { model.startImport() }
                .disabled(model.foundProfile == nil)
                .opacity(model.foundProfile == nil ? 0.4 : 1)
        }
        .onAppear { focused = true }
    }
}

/// The live result under the username field.
private struct LookupRow: View {
    let lookup: OnboardingModel.Lookup
    let platform: ImportPlatform?
    let typed: String

    var body: some View {
        switch lookup {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: DS.Spacing.s) {
                ProgressView().controlSize(.small).tint(DS.Color.textSecondary)
                Text("Looking for \(typed.trimmingCharacters(in: .whitespaces))…")
            }
            .font(DS.Font.subheadline)
            .foregroundStyle(DS.Color.textSecondary)
            .padding(.horizontal, DS.Spacing.m)
        case .notFound:
            Text("No \(platform?.title ?? "") player called “\(typed.trimmingCharacters(in: .whitespaces))”.")
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.horizontal, DS.Spacing.m)
        case .failed(let message):
            Text(message)
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.horizontal, DS.Spacing.m)
        case .found(let profile):
            HStack(spacing: DS.Spacing.sm) {
                PlayerAvatar(url: profile.avatarURL, rating: profile.currentRating ?? 800, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DS.Spacing.xs) {
                        if let title = profile.title {
                            Text(title)
                                .font(DS.Font.caption.weight(.bold))
                                .foregroundStyle(DS.Color.onAccent)
                                .padding(.horizontal, 4)
                                .background(DS.Color.accent, in: RoundedRectangle(cornerRadius: 3))
                        }
                        Text(profile.realName ?? profile.username)
                            .font(DS.Font.headline)
                            .foregroundStyle(DS.Color.text)
                            .lineLimit(1)
                    }
                    if let rating = profile.currentRating, let key = profile.currentRatingKey {
                        HStack(spacing: DS.Spacing.xs) {
                            Text(key.capitalized)
                            Text(rating, format: .number.grouping(.never)).monospaced()
                        }
                        .font(DS.Font.subheadline)
                        .foregroundStyle(DS.Color.textSecondary)
                    } else {
                        Text("No rated games yet")
                            .font(DS.Font.subheadline)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(DS.Color.accent)
            }
            .padding(DS.Spacing.sm)
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// The platform avatar if there is one, else the player's tier piece on a board-dark tile.
struct PlayerAvatar: View {
    let url: URL?
    let rating: Int
    var size: CGFloat = 40

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AvatarTile.radius(size))
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } else { fallback }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        PieceArt(kind: RatingTier(rating: rating).pieceKind, size: size * 0.86)
            .frame(width: size, height: size)
            .background(DS.Color.boardDark)
    }
}

// MARK: New-player questions

struct QuestionStep: View {
    let model: OnboardingModel
    let index: Int

    private struct Option { let title: String; let detail: String; let fen: String }

    private var question: (title: String, options: [Option]) {
        switch index {
        case 0:
            ("How well do you know the rules?", [
                Option(title: "I'm learning how pieces move", detail: "The board still looks busy", fen: "8/8/8/3N4/8/8/8/8 w - - 0 1"),
                Option(title: "I know the rules", detail: "Castling, en passant, the lot", fen: "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"),
                Option(title: "I know some tactics", detail: "Forks, pins, back-rank mates", fen: "r3k3/8/8/1N6/8/8/8/4K3 w - - 0 1"),
            ])
        case 1:
            ("Have you played full games?", [
                Option(title: "Not yet", detail: "This will be my first", fen: Rules.startFen),
                Option(title: "A few", detail: "Against friends or an app", fen: "r1bq1rk1/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQ1RK1 w - - 0 6"),
                Option(title: "Lots, just casually", detail: "No rating I'd show anyone", fen: "8/5pk1/6p1/8/3R4/6P1/5PK1/3r4 w - - 0 40"),
            ])
        default:
            ("What do you want first?", [
                Option(title: "Win more games", detail: "Stop giving pieces away", fen: "4k3/8/8/3q4/8/2N5/8/4K3 w - - 0 1"),
                Option(title: "Know what to play early", detail: "Openings that make sense", fen: "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3"),
                Option(title: "Finish games", detail: "Checkmate patterns", fen: "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1"),
            ])
        }
    }

    var body: some View {
        let q = question
        OnboardingScaffold(model: model, title: q.title, subtitle: "Question \(index + 1) of 3") {
            VStack(spacing: DS.Spacing.sm) {
                ForEach(Array(q.options.enumerated()), id: \.offset) { i, option in
                    ChoiceCard(leading: {
                        MiniBoard(fen: option.fen).frame(width: 56, height: 56)
                    }, title: option.title, detail: option.detail, selected: model.answers[index] == i) {
                        model.answer(index, i)
                    }
                }
            }
        } footer: { EmptyView() }
    }
}
