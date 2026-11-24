import SwiftUI
import ChessCore

/// The chessboard. Squares, highlights and coordinates are drawn in one `Canvas`; pieces
/// are views keyed by `TrackedPiece.id` so a move animates the same view to its new square.
/// Tap-to-move and drag-and-drop go through `BoardInteraction`; `onMove` receives UCI
/// (with a promotion suffix once `PromotionPicker` is answered) and returns whether the
/// move was accepted. Only the side to move in `fen` can move, and only when `interactive`.
///
/// `squareTint` colours are drawn at 45 %, `arrows` at 85 % of the given colour.
struct BoardView: View {
    let tracker: PieceTracker
    let fen: String
    let orientation: Piece.Color
    /// Contract: the caller must pass `interactive == (sideToMove == userColor) && phase == .userTurn`.
    /// When interactive, BoardView lets the side to move in `fen` play; it does not know the user's colour.
    let interactive: Bool
    let lastMove: (Square, Square)?
    let squareTint: [Square: Color]
    let badges: [Square: MoveClass]
    let arrows: [(Square, Square, Color)]
    let onMove: (String) -> Bool

    init(
        tracker: PieceTracker,
        fen: String,
        orientation: Piece.Color,
        interactive: Bool,
        lastMove: (Square, Square)?,
        squareTint: [Square: Color],
        badges: [Square: MoveClass],
        arrows: [(Square, Square, Color)],
        onMove: @escaping (String) -> Bool
    ) {
        self.tracker = tracker
        self.fen = fen
        self.orientation = orientation
        self.interactive = interactive
        self.lastMove = lastMove
        self.squareTint = squareTint
        self.badges = badges
        self.arrows = arrows
        self.onMove = onMove
    }

    @State private var interaction = BoardInteraction()
    @State private var drag: Drag?
    @State private var promotion: PendingPromotion?
    @State private var movesPlayed = 0
    @AppStorage(Pref.coordinates) private var showsCoordinates = Pref.Default.coordinates  // Settings

    private struct Drag: Equatable {
        let from: Square
        var location: CGPoint
        var lifted = false
        /// The piece was already selected when the finger came down; a plain tap then deselects it.
        let wasSelected: Bool
    }

    private struct PendingPromotion: Identifiable {
        let from: Square
        let to: Square
        let color: Piece.Color
        var id: String { from.notation + to.notation }
    }

    enum Style {
        static let tintOpacity = 0.45
        static let highlightOpacity = 0.30
        static let hintOpacity = 0.22
        static let dotFraction: CGFloat = 0.30
        static let captureRing: CGFloat = 4
        static let liftScale: CGFloat = 1.2
        /// Finger travel before a press on a piece becomes a drag.
        static let liftDistance: CGFloat = 4
        /// How far the badge hangs over the destination square's top-right corner.
        static let badgeOverhang: CGFloat = 6
        static let badgeDiameter: CGFloat = 26
        static let move = Animation.snappy(duration: 0.22)
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack(alignment: .topLeading) {
                squares
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.small))
                pieces(side: side)
                ArrowOverlay(arrows: arrows, orientation: orientation)
                badgeLayer(side: side)
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(gesture(side: side), including: interactive ? .all : .none)
        }
        .aspectRatio(1, contentMode: .fit)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .sensoryFeedback(.impact(weight: .light), trigger: movesPlayed)
        .onChange(of: fen) { reset() }
        .onChange(of: interactive) { reset() }
        .sheet(item: $promotion) { request in
            PromotionPicker(color: request.color) { kind in
                promotion = nil
                commit(request.id + PromotionPicker.suffix(kind))
            }
            .presentationDetents([.height(PromotionPicker.sheetHeight)])
        }
    }

    // MARK: Squares, highlights, hints, coordinates

    private var squares: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let cell = side / 8
            let occupied = Set(tracker.pieces.map(\.square))
            var highlighted = Set<Square>()
            if let lastMove { highlighted.formUnion([lastMove.0, lastMove.1]) }
            if let selected = interaction.selected { highlighted.insert(selected) }

            for square in Square.allCases {
                let rect = BoardGeometry.rect(for: square, orientation: orientation, side: side)
                let light = Self.isLight(square)
                context.fill(Path(rect), with: .color(light ? DS.Color.boardLight : DS.Color.boardDark))

                if let tint = squareTint[square] {
                    context.fill(Path(rect), with: .color(tint.opacity(Style.tintOpacity)))
                } else if highlighted.contains(square) {
                    context.fill(Path(rect), with: .color(DS.Color.accent.opacity(Style.highlightOpacity)))
                }
                if showsCoordinates { drawCoordinates(for: square, in: rect, light: light, context: context) }
            }

            let hint = GraphicsContext.Shading.color(DS.Color.ink.opacity(Style.hintOpacity))
            for target in interaction.targets {
                let rect = BoardGeometry.rect(for: target, orientation: orientation, side: side)
                if occupied.contains(target) {
                    let inset = rect.insetBy(dx: Style.captureRing / 2, dy: Style.captureRing / 2)
                    context.stroke(Path(ellipseIn: inset), with: hint, lineWidth: Style.captureRing)
                } else {
                    let d = cell * Style.dotFraction
                    let dot = CGRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d)
                    context.fill(Path(ellipseIn: dot), with: hint)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Rank numbers top-left in the left column, file letters bottom-right in the bottom row,
    /// each in the opposite square colour.
    private func drawCoordinates(for square: Square, in rect: CGRect, light: Bool, context: GraphicsContext) {
        let color = light ? DS.Color.boardDark : DS.Color.boardLight
        let inset: CGFloat = 3
        let leftFile: Square.File = orientation == .white ? .a : .h
        let bottomRank = orientation == .white ? 1 : 8
        if square.file == leftFile {
            let label = Text(String(square.rank.value)).font(DS.Font.label).foregroundStyle(color)
            context.draw(label, at: CGPoint(x: rect.minX + inset, y: rect.minY + inset - 1), anchor: .topLeading)
        }
        if square.rank.value == bottomRank {
            let label = Text(square.file.rawValue).font(DS.Font.label).foregroundStyle(color)
            context.draw(label, at: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset + 1), anchor: .bottomTrailing)
        }
    }

    static func isLight(_ square: Square) -> Bool {
        (square.file.number + square.rank.value).isMultiple(of: 2) == false
    }

    // MARK: Pieces

    private func pieces(side: CGFloat) -> some View {
        let cell = side / 8
        return ZStack(alignment: .topLeading) {
            ForEach(tracker.pieces) { tracked in
                let rect = BoardGeometry.rect(for: tracked.square, orientation: orientation, side: side)
                let fingerAt = drag.flatMap { $0.lifted && $0.from == tracked.square ? $0.location : nil }
                let dragged = fingerAt != nil
                PieceImage(piece: tracked.piece)
                    .frame(width: cell, height: cell)
                    .scaleEffect(dragged ? Style.liftScale : 1)
                    .position(fingerAt ?? CGPoint(x: rect.midX, y: rect.midY))
                    .zIndex(dragged ? 1 : 0)
                    .accessibilityLabel(Self.spoken(tracked.piece))
            }
        }
        .frame(width: side, height: side)
        .animation(Style.move, value: tracker)
        .allowsHitTesting(false)
    }

    static func spoken(_ piece: Piece) -> String {
        "\(piece.color == .white ? "White" : "Black") \(PromotionPicker.name(piece.kind).lowercased()), \(piece.square.notation)"
    }

    // MARK: Badges

    private func badgeLayer(side: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(badges.sorted { $0.key.rawValue < $1.key.rawValue }, id: \.key) { square, moveClass in
                MoveBadge(moveClass: moveClass)
                    .position(Self.badgeCenter(for: square, orientation: orientation, side: side))
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }

    /// The badge hangs `badgeOverhang` over the square's top-right corner, pulled back inside
    /// the board on the top and right edges so nothing is cut off.
    static func badgeCenter(for square: Square, orientation: Piece.Color, side: CGFloat) -> CGPoint {
        let rect = BoardGeometry.rect(for: square, orientation: orientation, side: side)
        let radius = Style.badgeDiameter / 2
        let x = rect.maxX + Style.badgeOverhang - radius
        let y = rect.minY - Style.badgeOverhang + radius
        return CGPoint(x: min(x, side - radius), y: max(y, radius))
    }

    // MARK: Gestures

    private func gesture(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if var current = drag {
                    current.location = value.location
                    if hypot(value.translation.width, value.translation.height) > Style.liftDistance {
                        current.lifted = true
                    }
                    drag = current
                    return
                }
                guard let square = BoardGeometry.square(at: value.startLocation, orientation: orientation, side: side),
                      let position = Position(fen: fen),
                      position.piece(at: square)?.color == position.sideToMove
                else { return }
                let wasSelected = interaction.selected == square
                if !wasSelected { _ = interaction.tap(square, fen: fen, side: position.sideToMove) }
                drag = Drag(from: square, location: value.location, wasSelected: wasSelected)
            }
            .onEnded { value in
                guard let sideToMove = Position(fen: fen)?.sideToMove else { return }
                let released = drag
                guard let released, released.lifted else {
                    drag = nil
                    // A press without travel is a tap. Pressing a piece selected it already;
                    // pressing the piece that was selected before deselects it.
                    if let released {
                        if released.wasSelected { interaction.clear() }
                    } else if let square = BoardGeometry.square(at: value.location, orientation: orientation, side: side) {
                        handle(interaction.tap(square, fen: fen, side: sideToMove), color: sideToMove)
                    }
                    return
                }
                let target = BoardGeometry.square(at: value.location, orientation: orientation, side: side)
                withAnimation(Style.move) {
                    drag = nil
                    if let target {
                        handle(interaction.drop(from: released.from, to: target, fen: fen, side: sideToMove), color: sideToMove)
                    }
                }
            }
    }

    private func handle(_ result: BoardInteraction.TapResult, color: Piece.Color) {
        switch result {
        case .move(let uci):
            commit(uci)
        case .needsPromotion(let from, let to):
            promotion = PendingPromotion(from: from, to: to, color: color)
        case .selected, .cleared:
            break
        }
    }

    private func commit(_ uci: String) {
        if onMove(uci) { movesPlayed += 1 }
    }

    /// A new position or a locked board drops any selection, drag or open promotion.
    private func reset() {
        interaction.clear()
        drag = nil
        promotion = nil
    }
}

/// One piece from the asset catalogue (`Pieces/<colour><kind>`), aspect-fit.
struct PieceImage: View {
    let piece: Piece

    var body: some View {
        Image(Self.assetName(piece))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }

    static func assetName(_ piece: Piece) -> String {
        let kind = piece.kind == .pawn ? "p" : piece.kind.rawValue.lowercased()
        return "Pieces/\(piece.color.rawValue)\(kind)"
    }
}

#if DEBUG
/// Static board states for previews and the screenshot test.
enum BoardSamples {
    /// 1.e4 e5 2.Nf3 Nc6 3.Ng5?? — Black to move; White should have played Bc4.
    static let ng5Fen = "r1bqkbnr/pppp1ppp/2n5/4p1N1/4P3/8/PPPP1PPP/RNBQKB1R b KQkq - 3 3"

    @MainActor static var ng5Blunder: some View {
        BoardView(
            tracker: PieceTracker(fen: ng5Fen),
            fen: ng5Fen,
            orientation: .white,
            interactive: false,
            lastMove: (Square("f3"), Square("g5")),
            squareTint: [Square("g5"): DS.Color.moveClass(.blunder)],
            badges: [Square("g5"): .blunder],
            arrows: [(Square("f1"), Square("c4"), DS.Color.accent)],
            onMove: { _ in false }
        )
        .padding(.horizontal, DS.Spacing.s)
        .overlay(alignment: .leading) {
            EvalBar(whiteCp: -280, orientation: .white).padding(.leading, 1)
        }
    }
}

#Preview("Ng5 blunder") {
    BoardSamples.ng5Blunder
        .frame(maxHeight: .infinity)
        .background(DS.Color.background)
        .preferredColorScheme(.dark)
}

#Preview("Promotion") {
    PromotionPicker(color: .white) { _ in }
        .background(DS.Color.background)
        .preferredColorScheme(.dark)
}
#endif
