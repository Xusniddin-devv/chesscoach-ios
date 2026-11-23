import SwiftUI
import ChessCore

/// One ply in the move strip. `ply` is 1-based (the move's index in the game plus one), the
/// same numbering as `GameSession.verdicts`. `moveClass` is set once the move is graded and
/// the grade may be shown.
struct MoveStripItem: Identifiable, Equatable {
    let ply: Int
    let san: String
    let moveClass: MoveClass?
    /// Review: a move of a line tried on the board (not the game), drawn on a quiet tile.
    var isBranch = false

    var id: Int { ply }
}

/// One numbered move: White's ply and Black's reply. A game that starts with Black to move
/// opens with a group that has only Black's ply ("5…").
struct MoveStripGroup: Equatable {
    let number: Int
    let white: MoveStripItem?
    let black: MoveStripItem?

    var label: String { white == nil ? "\(number)…" : "\(number)." }

    static func groups(_ items: [MoveStripItem], startFen: String) -> [MoveStripGroup] {
        let fields = startFen.split(separator: " ")
        let blackFirst = fields.count > 1 && fields[1] == "b"
        var number = fields.count > 5 ? Int(fields[5]) ?? 1 : 1
        var result: [MoveStripGroup] = []
        var index = 0
        if blackFirst, let first = items.first {
            result.append(MoveStripGroup(number: number, white: nil, black: first))
            number += 1
            index = 1
        }
        while index < items.count {
            let black = index + 1 < items.count ? items[index + 1] : nil
            result.append(MoveStripGroup(number: number, white: items[index], black: black))
            number += 1
            index += 2
        }
        return result
    }
}

/// The game's moves in one horizontal, scrollable line: "1. e4 e5 2. Nf3 …". The current
/// ply carries an accent underline and stays scrolled into view; a graded user move shows
/// its class glyph in the class colour. Tapping a ply selects it.
struct MoveStrip: View {
    let items: [MoveStripItem]
    let startFen: String
    /// The highlighted ply; nil highlights nothing (the start position).
    let currentPly: Int?
    let onSelect: (Int) -> Void

    static let height: CGFloat = 36

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: DS.Spacing.sm) {
                    if items.isEmpty {
                        Text("No moves yet")
                            .font(DS.Font.subheadline)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    ForEach(MoveStripGroup.groups(items, startFen: startFen), id: \.number) { group in
                        HStack(spacing: DS.Spacing.xs) {
                            Text(group.label)
                                .font(DS.Font.subheadline.monospacedDigit())
                                .foregroundStyle(DS.Color.textSecondary)
                            if let white = group.white { ply(white) }
                            if let black = group.black { ply(black) }
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.m)
                .frame(minHeight: Self.height)
            }
            .scrollIndicators(.hidden)
            .frame(height: Self.height)
            .onAppear { proxy.scrollTo(currentPly, anchor: .center) }
            .onChange(of: currentPly) { _, ply in
                withAnimation(.snappy) { proxy.scrollTo(ply, anchor: .center) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Moves")
    }

    private func ply(_ item: MoveStripItem) -> some View {
        let current = item.ply == currentPly
        return Button { onSelect(item.ply) } label: {
            HStack(spacing: 2) {
                Text(item.san)
                    .font(DS.Font.subheadline.weight(current ? .semibold : .regular))
                    .foregroundStyle(current ? DS.Color.text : DS.Color.text.opacity(0.8))
                if let moveClass = item.moveClass {
                    Text(moveClass.glyph)
                        .font(DS.Font.badgeGlyph)
                        .foregroundStyle(DS.Color.moveClass(moveClass))
                }
            }
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.vertical, DS.Spacing.xs)
            .background {
                if item.isBranch {
                    RoundedRectangle(cornerRadius: 6).fill(DS.Color.surface2)
                }
            }
            .overlay(alignment: .bottom) {
                if current {
                    Capsule().fill(DS.Color.accent).frame(height: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(item.ply)
        .accessibilityLabel((item.moveClass.map { "\(item.san), \($0.label)" } ?? item.san)
                            + (item.isBranch ? ", your line" : ""))
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}
