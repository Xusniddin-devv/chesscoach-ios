public enum MoveClass: String, Codable, CaseIterable, Sendable {
    case book, brilliant, great, best, excellent, good, forced, inaccuracy, mistake, miss, blunder

    public var label: String {
        switch self {
        case .book: "Book"
        case .brilliant: "Brilliant"
        case .great: "Great"
        case .best: "Best"
        case .excellent: "Excellent"
        case .good: "Good"
        case .forced: "Forced"
        case .inaccuracy: "Inaccuracy"
        case .mistake: "Mistake"
        case .miss: "Miss"
        case .blunder: "Blunder"
        }
    }

    public var glyph: String {
        switch self {
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

    public var isNegative: Bool {
        switch self {
        case .inaccuracy, .mistake, .miss, .blunder: true
        default: false
        }
    }
}
