import SwiftUI
import ChessCore

/// What a tap on the editor's board does.
enum EditorTool: Equatable {
    case piece(SetupPiece)
    case eraser
}

/// The visual position editor (no FEN on screen): the board, a tray of the 12 pieces and an
/// eraser, side to move, castling, "Clear board" / "Start position", and one inline message
/// when the position can't be analysed (`PositionValidator`). Pick a piece and tap squares to
/// place it (tapping the same piece again removes it), drag pieces around the board, drag one
/// off the board to remove it, or drag from the tray onto a square.
/// "Analyse this position" hands the FEN back to the analysis board.
struct PositionEditorView: View {
    let onAnalyse: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var setup: BoardSetup
    @State private var orientation: Piece.Color
    @State private var tool: EditorTool?
    /// A piece dragged from the tray, at the finger (in the editor's coordinate space).
    @State private var trayDrag: (piece: SetupPiece, location: CGPoint)?
    @State private var boardFrame: CGRect = .zero

    nonisolated static let space = "editor"

    init(fen: String, onAnalyse: @escaping (String) -> Void) {
        let setup = BoardSetup(fen: fen) ?? .start
        _setup = State(initialValue: setup)
        _orientation = State(initialValue: .white)
        self.onAnalyse = onAnalyse
    }

    private var problems: [PositionProblem] { PositionValidator.problems(setup) }

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.sm) {
                EditorBoard(setup: $setup, orientation: orientation, tool: tool)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { boardFrame = $0 }
                    .padding(.horizontal, DS.Spacing.s)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: DS.Spacing.sm) {
                    tray
                    settings
                    message
                    PrimaryButton(title: "Analyse this position") {
                        onAnalyse(setup.fen)
                        dismiss()
                    }
                    .disabled(!problems.isEmpty)
                    .opacity(problems.isEmpty ? 1 : 0.4)
                }
                .padding(.horizontal, DS.Spacing.m)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, DS.Spacing.s)
            .padding(.bottom, DS.Spacing.s)
            .overlay(alignment: .topLeading) { dragGhost }
            .coordinateSpace(.named(Self.space))
            .background(DS.Color.background.ignoresSafeArea())
            .navigationTitle("Edit position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { withAnimation(.snappy) { orientation = orientation.opposite } } label: {
                        Image("Icons/flip").renderingMode(.template).resizable().frame(width: 20, height: 20)
                    }
                    .accessibilityLabel("Flip board")
                }
            }
            .tint(DS.Color.text)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Tray

    /// Two rows of six pieces (White, Black) and a tall eraser cell on the right.
    private var tray: some View {
        HStack(spacing: DS.Spacing.xs) {
            VStack(spacing: DS.Spacing.xs) {
                trayRow(.white)
                trayRow(.black)
            }
            Button { select(.eraser) } label: {
                Image("Icons/eraser")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(DS.Color.text)
                    .frame(width: 44)
                    .frame(maxHeight: .infinity)
                    .background(selectionBackground(tool == .eraser))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Eraser")
            .accessibilityAddTraits(tool == .eraser ? .isSelected : [])
        }
        .padding(DS.Spacing.s)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
    }

    private func trayRow(_ color: Piece.Color) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(SetupPiece.trayKinds, id: \.self) { kind in
                let piece = SetupPiece(color, kind)
                PieceImage(piece: Piece(kind, color: color, square: .a1))
                    .padding(3)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(selectionBackground(tool == .piece(piece)))
                    .contentShape(Rectangle())
                    .opacity(trayDrag?.piece == piece ? 0.35 : 1)
                    .gesture(trayGesture(piece))
                    .accessibilityElement()
                    .accessibilityLabel("\(color == .white ? "White" : "Black") \(PromotionPicker.name(kind).lowercased())")
                    .accessibilityAddTraits(tool == .piece(piece) ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { select(.piece(piece)) }
            }
        }
    }

    private func selectionBackground(_ selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.small)
            .fill(selected ? DS.Color.surface2 : .clear)
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.small).stroke(selected ? DS.Color.accent : .clear, lineWidth: 2))
    }

    private func select(_ next: EditorTool) {
        withAnimation(.snappy(duration: 0.15)) { tool = tool == next ? nil : next }
    }

    /// A tap picks the piece as the tool; a drag carries it onto a square.
    private func trayGesture(_ piece: SetupPiece) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if hypot(value.translation.width, value.translation.height) > 6 {
                    trayDrag = (piece, value.location)
                }
            }
            .onEnded { value in
                defer { trayDrag = nil }
                guard trayDrag != nil else { select(.piece(piece)); return }
                let point = CGPoint(x: value.location.x - boardFrame.minX, y: value.location.y - boardFrame.minY)
                if let square = BoardGeometry.square(at: point, orientation: orientation, side: boardFrame.width) {
                    withAnimation(.snappy(duration: 0.2)) { EditorBoard.place(piece, on: square, in: &setup) }
                }
            }
    }

    @ViewBuilder private var dragGhost: some View {
        if let drag = trayDrag {
            let size = boardFrame.width / 8 * 1.2
            PieceImage(piece: Piece(drag.piece.kind, color: drag.piece.color, square: .a1))
                .frame(width: size, height: size)
                .position(drag.location)
                .allowsHitTesting(false)
        }
    }

    // MARK: Settings

    private var settings: some View {
        VStack(spacing: DS.Spacing.sm) {
            Picker("Side to move", selection: $setup.sideToMove) {
                Text("White to move").tag(Piece.Color.white)
                Text("Black to move").tag(Piece.Color.black)
            }
            .pickerStyle(.segmented)
            castlingRow(.white)
            castlingRow(.black)
            HStack(spacing: DS.Spacing.s) {
                quietButton("Clear board") { setup = .empty }
                quietButton("Start position") { setup = .start }
            }
        }
    }

    private func castlingRow(_ color: Piece.Color) -> some View {
        HStack(spacing: DS.Spacing.s) {
            Text("\(color == .white ? "White" : "Black") can castle")
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
            Spacer(minLength: DS.Spacing.s)
            castlingChip(color == .white ? .whiteKingside : .blackKingside, title: "Kingside")
            castlingChip(color == .white ? .whiteQueenside : .blackQueenside, title: "Queenside")
        }
    }

    /// On: a light chip with ink text; off: `surface2`. Greyed out when the king or rook has left
    /// its home square (the choice is kept for when it comes back).
    private func castlingChip(_ right: CastlingRight, title: String) -> some View {
        let available = setup.availableCastling.contains(right)
        let on = setup.effectiveCastling.contains(right)
        return Button {
            if setup.castling.contains(right) { setup.castling.remove(right) } else { setup.castling.insert(right) }
        } label: {
            Text(title)
                .font(DS.Font.subheadline.weight(.semibold))
                .foregroundStyle(on ? DS.Color.ink : DS.Color.textSecondary)
                .padding(.horizontal, DS.Spacing.sm)
                .frame(height: 32)
                .background(on ? DS.Color.text : DS.Color.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.3)
        .accessibilityLabel("\(right.color == .white ? "White" : "Black") castles \(title.lowercased())")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy(duration: 0.25)) { action() } } label: {
            Text(title)
                .font(DS.Font.subheadline.weight(.semibold))
                .foregroundStyle(DS.Color.text)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
        }
        .buttonStyle(.plain)
    }

    /// The first problem, or a hint while nothing is selected.
    private var message: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
            if let problem = problems.first {
                Circle().fill(DS.Color.moveClass(.inaccuracy)).frame(width: 7, height: 7)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(problem.message).foregroundStyle(DS.Color.text)
            } else {
                Text(tool == nil ? "Pick a piece below, then tap a square." : "Ready to analyse.")
                    .foregroundStyle(DS.Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .font(DS.Font.subheadline)
        .frame(minHeight: 20)
        .padding(.horizontal, DS.Spacing.xs)
        .animation(.snappy(duration: 0.2), value: problems.first)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Board

/// The editor's board: squares, coordinates, the pieces of `setup`. A tap applies the tool;
/// a drag moves a piece (off the board removes it).
struct EditorBoard: View {
    @Binding var setup: BoardSetup
    let orientation: Piece.Color
    let tool: EditorTool?

    @State private var drag: (from: Square, location: CGPoint)?

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack(alignment: .topLeading) {
                squares(side: side)
                ForEach(setup.pieces.sorted { $0.key.rawValue < $1.key.rawValue }, id: \.key) { square, piece in
                    let rect = BoardGeometry.rect(for: square, orientation: orientation, side: side)
                    let dragged = drag?.from == square
                    PieceImage(piece: Piece(piece.kind, color: piece.color, square: square))
                        .frame(width: rect.width, height: rect.height)
                        .scaleEffect(dragged ? 1.2 : 1)
                        .position(dragged ? drag!.location : CGPoint(x: rect.midX, y: rect.midY))
                        .zIndex(dragged ? 1 : 0)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(gesture(side: side))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.impact(weight: .light), trigger: setup)
        .accessibilityElement()
        .accessibilityLabel("Board, \(setup.pieces.count) pieces")
    }

    private func squares(side: CGFloat) -> some View {
        Canvas { context, _ in
            for square in Square.allCases {
                let rect = BoardGeometry.rect(for: square, orientation: orientation, side: side)
                let light = BoardView.isLight(square)
                context.fill(Path(rect), with: .color(light ? DS.Color.boardLight : DS.Color.boardDark))
                let color = light ? DS.Color.boardDark : DS.Color.boardLight
                if square.file == (orientation == .white ? .a : .h) {
                    context.draw(Text(String(square.rank.value)).font(DS.Font.label).foregroundStyle(color),
                                 at: CGPoint(x: rect.minX + 3, y: rect.minY + 2), anchor: .topLeading)
                }
                if square.rank.value == (orientation == .white ? 1 : 8) {
                    context.draw(Text(square.file.rawValue).font(DS.Font.label).foregroundStyle(color),
                                 at: CGPoint(x: rect.maxX - 3, y: rect.maxY - 2), anchor: .bottomTrailing)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.small))
    }

    private func gesture(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let travel = hypot(value.translation.width, value.translation.height)
                if let current = drag {
                    drag = (current.from, value.location)
                } else if travel > 6,
                          let from = BoardGeometry.square(at: value.startLocation, orientation: orientation, side: side),
                          setup[from] != nil {
                    drag = (from, value.location)
                }
            }
            .onEnded { value in
                if let current = drag {
                    let target = BoardGeometry.square(at: value.location, orientation: orientation, side: side)
                    withAnimation(.snappy(duration: 0.2)) {
                        drag = nil
                        guard target != current.from, let piece = setup[current.from] else { return }
                        setup[current.from] = nil
                        if let target { Self.place(piece, on: target, in: &setup) }
                    }
                    return
                }
                guard let square = BoardGeometry.square(at: value.location, orientation: orientation, side: side) else { return }
                withAnimation(.snappy(duration: 0.2)) {
                    switch tool {
                    case .piece(let piece):
                        if setup[square] == piece { setup[square] = nil } else { Self.place(piece, on: square, in: &setup) }
                    case .eraser:
                        setup[square] = nil
                    case nil:
                        break
                    }
                }
            }
    }

    /// Places `piece`; a king moves rather than doubles (the other king of its colour leaves).
    static func place(_ piece: SetupPiece, on square: Square, in setup: inout BoardSetup) {
        if piece.kind == .king {
            for (other, existing) in setup.pieces where existing == piece && other != square {
                setup[other] = nil
            }
        }
        setup[square] = piece
    }
}

#Preview {
    PositionEditorView(fen: Rules.startFen) { _ in }
}
