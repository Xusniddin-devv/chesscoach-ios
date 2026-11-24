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

            PrimaryButton(title: "Get started") { model.go(.find) }
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
    var height: CGFloat = 150

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
        .frame(height: height)
        .accessibilityHidden(true)
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
        PieceArt(kind: RatingTier(rating: rating).piece, size: size * 0.86)
            .frame(width: size, height: size)
            .background(DS.Color.boardDark)
    }
}

