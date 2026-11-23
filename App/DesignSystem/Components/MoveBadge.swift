import SwiftUI
import ChessCore

/// Small colored disc carrying the class glyph (glyphs from web-rules.md).
struct MoveBadge: View {
    let moveClass: MoveClass

    var body: some View {
        Text(Self.glyph(moveClass))
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(DS.Color.onAccent)
            .frame(width: 22, height: 22)
            .background(DS.Color.moveClass(moveClass), in: Circle())
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
