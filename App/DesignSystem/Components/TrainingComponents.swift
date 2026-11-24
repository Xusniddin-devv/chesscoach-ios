import SwiftUI
import ChessCore

/// "12 day streak": capsule on `surface2`, numeral in mono accent, the words in sentence
/// case (no all-caps tracked label). No flame emoji.
struct StreakPill: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(count, format: .number.grouping(.never))
                .font(DS.Font.numeral)
                .foregroundStyle(DS.Color.accent)
            Text("day streak")
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.s - 2)
        .background(DS.Color.surface2, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) day streak")
    }
}

/// Completion ring: a `surface2` stroke, a full accent ring with an ink centre once done.
struct DoneRing: View {
    let done: Bool
    var size: CGFloat = 28

    var body: some View {
        let line = max(2, size / 9)
        ZStack {
            Circle().strokeBorder(DS.Color.surface2, lineWidth: line)
            if done {
                Circle().fill(DS.Color.accent)
                Circle().fill(DS.Color.ink).frame(width: size * 0.28, height: size * 0.28)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(done ? "Done" : "Not done")
    }
}

/// A static board for cards and rows: squares and pieces, no coordinates or interaction.
struct MiniBoard: View {
    let fen: String
    var orientation: Piece.Color = .white

    var body: some View {
        let pieces = Position(fen: fen)?.pieces ?? []
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / 8
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for square in Square.allCases {
                        let rect = BoardGeometry.rect(for: square, orientation: orientation, side: side)
                        context.fill(Path(rect), with: .color(BoardView.isLight(square) ? DS.Color.boardLight : DS.Color.boardDark))
                    }
                }
                ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                    let rect = BoardGeometry.rect(for: piece.square, orientation: orientation, side: side)
                    PieceImage(piece: piece)
                        .frame(width: cell, height: cell)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.small / 2))
        .accessibilityHidden(true)
    }
}

/// Selectable capsule. Selected = inverted (`text` fill, ink label), so the accent stays
/// reserved for the screen's one primary action.
struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Font.subheadline.weight(.medium))
                .foregroundStyle(selected ? DS.Color.ink : DS.Color.text)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.s)
                .background(selected ? DS.Color.text : DS.Color.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// An Icons8 template icon from the asset catalog (`Icons/<name>`), tinted by the
/// foreground style. The one icon pack used across the app.
struct IconImage: View {
    let name: String
    var size: CGFloat = 20

    init(_ name: String, size: CGFloat = 20) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image("Icons/\(name)")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A section title on the tab screens (Profile's style): 20 pt semibold, sentence case.
struct ScreenSectionTitle: View {
    let text: String
    var trailing: String? = nil

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(DS.Color.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing {
                Text(verbatim: trailing)
                    .font(DS.Font.subheadline.monospacedDigit())
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
    }
}

/// Progress as board squares (Profile's tier track): one cell per item, done cells alternate
/// board light and dark, open ones are `surface2`.
struct SquareProgress: View {
    let done: Int
    let total: Int
    var cell: CGFloat = 12

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < done ? (i % 2 == 0 ? DS.Color.boardLight : DS.Color.boardDark) : DS.Color.surface2)
                    .frame(width: cell, height: cell)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(done) of \(total) done")
    }
}

/// Wraps chips onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = DS.Spacing.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
