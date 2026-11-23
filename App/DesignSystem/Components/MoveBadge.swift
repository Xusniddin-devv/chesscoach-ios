import SwiftUI
import ChessCore

/// Small colored disc carrying the class glyph (glyphs from web-rules.md), with a
/// 2 pt ring so it separates from both board square colours.
struct MoveBadge: View {
    let moveClass: MoveClass

    var body: some View {
        Text(Self.glyph(moveClass))
            .font(DS.Font.badgeGlyph)
            .foregroundStyle(DS.Color.moveClassGlyph(moveClass))
            .frame(width: 22, height: 22)
            .background(DS.Color.moveClass(moveClass), in: Circle())
            .padding(2)
            .background(DS.Color.moveClassRing, in: Circle())
            .accessibilityLabel(moveClass.rawValue)
    }

    static func glyph(_ c: MoveClass) -> String {
        switch c {
        case .book: "B"
        case .brilliant: "!!"
        case .great: "!"
        case .best: "★"
        case .excellent, .good: "✓"
        case .forced: "→"
        case .inaccuracy: "?!"
        case .mistake: "?"
        case .miss: "✗"
        case .blunder: "??"
        }
    }
}
