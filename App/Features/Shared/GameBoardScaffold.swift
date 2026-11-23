import SwiftUI
import ChessCore

/// The board screen shared by Play and Review, top to bottom: move strip, opponent bar,
/// board, user bar, status line; the action bar (system glass) at the bottom.
///
/// The board is as wide as the screen allows (minus `DS.Spacing.s` on each side, where the
/// eval bar lives) and the whole stack is centred between the top safe area and the action
/// bar, so the free space splits evenly above and below. A bottom `card` (the coach card)
/// replaces the action bar while it is shown and never covers the board: when it would, the
/// board shrinks just enough (and, on small phones, the stack moves up into its free space).
struct GameBoardScaffold<Board: View, Actions: View, Card: View>: View {
    typealias StatusAccessory = BoardStatusAccessory

    let moves: [MoveStripItem]
    let startFen: String
    let currentPly: Int?
    let onSelectPly: (Int?) -> Void
    let top: PlayerBarModel
    let bottom: PlayerBarModel
    let status: String?
    let statusAccessory: StatusAccessory?
    let board: Board
    let actions: Actions
    let card: Card

    @State private var barHeight: CGFloat = 0
    @State private var cardHeight: CGFloat = 0

    /// - Parameter currentPly: the highlighted ply in the strip (nil: none).
    init(moves: [MoveStripItem], startFen: String = Rules.startFen, currentPly: Int?,
         onSelectPly: @escaping (Int?) -> Void, top: PlayerBarModel, bottom: PlayerBarModel,
         status: String?, statusAccessory: StatusAccessory? = nil,
         @ViewBuilder board: () -> Board, @ViewBuilder actions: () -> Actions,
         @ViewBuilder card: () -> Card) {
        self.moves = moves
        self.startFen = startFen
        self.currentPly = currentPly
        self.onSelectPly = onSelectPly
        self.top = top
        self.bottom = bottom
        self.status = status
        self.statusAccessory = statusAccessory
        self.board = board()
        self.actions = actions()
        self.card = card()
    }

    private var cardShown: Bool { cardHeight > 0 }

    /// How far the card reaches up into the stack's region (whose bottom is the action bar's
    /// top), plus a gap so the board never touches it.
    private var covered: CGFloat {
        cardShown ? cardHeight + Self.barBottomInset - barHeight + DS.Spacing.s : 0
    }

    /// The action bar and the card share this bottom inset, so the card sits where the bar was.
    private static var barBottomInset: CGFloat { DS.Spacing.s }

    var body: some View {
        BoardStackLayout(margin: DS.Spacing.s, covered: covered) {
            MoveStrip(items: moves, startFen: startFen, currentPly: currentPly) { onSelectPly($0) }
                .padding(.bottom, DS.Spacing.s)
            PlayerBar(model: top)
            board.layoutValue(key: BoardSlot.self, value: true)
            // Under the card; faded so nothing peeks out between the board and the card.
            PlayerBar(model: bottom)
                .opacity(cardShown ? 0 : 1)
            StatusLine(text: status, accessory: statusAccessory) { onSelectPly(nil) }
                .opacity(cardShown ? 0 : 1)
        }
        .safeAreaBar(edge: .bottom) {
            actions
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, Self.barBottomInset)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
                .opacity(cardShown ? 0 : 1)
                .allowsHitTesting(!cardShown)
                .accessibilityHidden(cardShown)
        }
        .overlay(alignment: .bottom) {
            // Always present (an empty stack is 0 pt), so the height also reports the card leaving.
            VStack(spacing: 0) { card }
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    withAnimation(.snappy(duration: 0.3)) { cardHeight = height }
                }
                .padding(.horizontal, DS.Spacing.s)
                .padding(.bottom, Self.barBottomInset)
        }
    }
}

extension GameBoardScaffold where Card == EmptyView {
    init(moves: [MoveStripItem], startFen: String = Rules.startFen, currentPly: Int?,
         onSelectPly: @escaping (Int?) -> Void, top: PlayerBarModel, bottom: PlayerBarModel,
         status: String?, statusAccessory: StatusAccessory? = nil,
         @ViewBuilder board: () -> Board, @ViewBuilder actions: () -> Actions) {
        self.init(moves: moves, startFen: startFen, currentPly: currentPly, onSelectPly: onSelectPly,
                  top: top, bottom: bottom, status: status, statusAccessory: statusAccessory,
                  board: board, actions: actions, card: { EmptyView() })
    }
}

// MARK: Geometry

/// Where the board stack goes in a region of `width` × `height`: the board's side and the
/// stack's top. `above` / `below` are the heights of everything over / under the board,
/// `covered` how far a bottom card reaches into the region (0: none).
///
/// Without a card the board is `width - 2 * margin` wide (less when the height runs out) and
/// the free space splits evenly above and below. With a card that would cover the board, the
/// board first shrinks in place by up to `preferredShrink` of its side (its top stays put),
/// then the stack moves up into its free space, then the board shrinks the rest.
struct BoardStackGeometry: Equatable {
    let top: CGFloat
    let side: CGFloat

    /// The share of the board's side it may lose before the stack moves instead.
    static let preferredShrink: CGFloat = 0.08

    init(width: CGFloat, height: CGFloat, margin: CGFloat, above: CGFloat, below: CGFloat, covered: CGFloat) {
        var side = max(0, min(width - 2 * margin, height - above - below))
        var top = max(0, (height - above - side - below) / 2)
        var deficit = covered > 0 ? top + above + side - (height - covered) : 0
        if deficit > 0 {
            let shrink = min(deficit, side * Self.preferredShrink)
            side -= shrink
            deficit -= shrink
            let shift = min(deficit, top)
            top -= shift
            deficit -= shift
            side = max(0, side - deficit)
        }
        self.top = top
        self.side = side
    }
}

private struct BoardSlot: LayoutValueKey {
    static let defaultValue = false
}

/// Stacks its subviews top to bottom with no spacing (subviews pad themselves); the subview
/// marked `BoardSlot` is the square board, placed by `BoardStackGeometry`. Animating
/// `covered` animates the board's size.
private struct BoardStackLayout: Layout {
    var margin: CGFloat
    var covered: CGFloat

    var animatableData: CGFloat {
        get { covered }
        set { covered = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let boardIndex = subviews.firstIndex { $0[BoardSlot.self] } ?? subviews.endIndex
        let heights = subviews.map { subview in
            subview[BoardSlot.self] ? 0 : subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
        }
        let above = heights[..<boardIndex].reduce(0, +)
        let below = heights[min(boardIndex + 1, heights.endIndex)...].reduce(0, +)
        let geometry = BoardStackGeometry(width: bounds.width, height: bounds.height, margin: margin,
                                          above: above, below: below, covered: covered)
        var y = bounds.minY + geometry.top
        for (index, subview) in subviews.enumerated() {
            if index == boardIndex {
                subview.place(at: CGPoint(x: bounds.midX, y: y), anchor: .top,
                              proposal: ProposedViewSize(width: geometry.side, height: geometry.side))
                y += geometry.side
            } else {
                subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: heights[index]))
                y += heights[index]
            }
        }
    }
}

// MARK: Status line

/// A trailing control in the status line.
enum BoardStatusAccessory {
    /// "Back to live" chip (selects nil); the dot says moves were played meanwhile.
    case backToLive(hasNewMoves: Bool)
    /// A quiet inline action, e.g. "Retry" after an engine error.
    case action(String, () -> Void)
}

/// One quiet line under the user bar: opening name, last verdict or "Pip is thinking…", with
/// an optional trailing chip or action.
private struct StatusLine: View {
    let text: String?
    let accessory: BoardStatusAccessory?
    let onBackToLive: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            Text(text ?? "")
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
            switch accessory {
            case .backToLive(let hasNewMoves):
                Button(action: onBackToLive) {
                    HStack(spacing: 6) {
                        if hasNewMoves {
                            Circle().fill(DS.Color.accent).frame(width: 6, height: 6)
                                .accessibilityHidden(true)
                        }
                        Text("Back to live")
                            .font(DS.Font.subheadline.weight(.semibold))
                            .foregroundStyle(DS.Color.text)
                    }
                    .padding(.horizontal, DS.Spacing.sm)
                    .frame(height: 30)
                    .background(DS.Color.surface2, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint(hasNewMoves ? "New moves were played" : "")
                .transition(.opacity)
            case .action(let title, let action):
                Button(title, action: action)
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.accent)
            case nil:
                EmptyView()
            }
        }
        .frame(height: 30)
        .padding(.horizontal, DS.Spacing.m)
        .padding(.top, DS.Spacing.s)
    }
}

// MARK: Action bar

/// The bottom bar's buttons: SF Symbol only, system glass. Groups of adjacent buttons share
/// one glass capsule (`ActionBarGroup`).
struct ActionBarButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isEnabled ? DS.Color.text : DS.Color.text.opacity(0.3))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Buttons sharing one glass capsule.
struct ActionBarGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .padding(.horizontal, 2)
            .glassEffect(.regular.interactive(), in: Capsule())
    }
}
