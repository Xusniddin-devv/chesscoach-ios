import Foundation

/// Turns a spoken move ("knight to c3", "e4", "bishop takes f7", "castle kingside",
/// "night f three") into a legal UCI move on a position. Port of the web app's
/// `src/lib/voiceMove.ts`, with three deliberate changes:
/// - a move that is still ambiguous after every hint returns nil instead of the first match
///   (playing a move the user did not mean is worse than asking again);
/// - two squares ("knight b1 c3", "e2 to e4") read as from → to;
/// - "promote to knight" filters by the pawn, not the knight, so under-promotion works.
public enum VoiceMove {
    static let numberWords: [String: String] = [
        "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8",
        // Common recogniser spellings of the same sounds.
        "won": "1", "for": "4", "ate": "8",
    ]

    /// Spoken letters, NATO words and homophones → files.
    static let fileWords: [String: Character] = [
        "alpha": "a", "bravo": "b", "charlie": "c", "delta": "d", "echo": "e", "foxtrot": "f",
        "golf": "g", "hotel": "h",
        "ay": "a", "bee": "b", "be": "b", "cee": "c", "see": "c", "sea": "c", "dee": "d",
        "ee": "e", "ef": "f", "eff": "f", "gee": "g", "aitch": "h",
    ]

    /// In the web's order: the first piece word found wins.
    static let pieceWords: [(String, Piece.Kind)] = [
        ("pawn", .pawn), ("knight", .knight), ("night", .knight), ("horse", .knight),
        ("bishop", .bishop), ("rook", .rook), ("rock", .rook), ("castle", .rook), ("tower", .rook),
        ("queen", .queen), ("king", .king),
    ]

    static let captureWords: Set<String> = ["take", "takes", "capture", "captures", "x"]
    static let promoteWords: Set<String> = ["promote", "promotes", "promotion", "promoting", "equals"]

    /// Lowercase words, punctuation dropped, number words as digits, "c 4" kept as two words.
    static func tokens(_ text: String) -> [String] {
        let cleaned = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").map { word in
            let w = String(word)
            if let digit = numberWords[w] { return digit }
            return w.hasSuffix("s") && w.count > 4 && pieceWord(String(w.dropLast())) != nil ? String(w.dropLast()) : w
        }
    }

    private static func pieceWord(_ w: String) -> Piece.Kind? {
        pieceWords.first { $0.0 == w }?.1
    }

    private static func file(_ word: String) -> Character? {
        if word.count == 1, let c = word.first, ("a"..."h").contains(c) { return c }
        return fileWords[word]
    }

    private static func isRank(_ word: String) -> Bool {
        word.count == 1 && ("1"..."8").contains(word.first!)
    }

    /// Squares in the order spoken: "c4", or a file word followed by a rank ("see 4", "c 4").
    static func squares(in tokens: [String]) -> [String] {
        var result: [String] = []
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            let chars = Array(t)
            if chars.count == 2, ("a"..."h").contains(chars[0]), ("1"..."8").contains(chars[1]) {
                result.append(t)
            } else if i + 1 < tokens.count, let f = file(t), isRank(tokens[i + 1]) {
                result.append("\(f)\(tokens[i + 1])")
                i += 1
            }
            i += 1
        }
        return result
    }

    struct Candidate {
        let uci: String
        let kind: Piece.Kind
        let isCapture: Bool
        let isCastle: Bool
        let san: String
    }

    /// Every legal move; a pawn reaching the last rank appears once per promotion piece.
    static func legalMoves(fen: String) -> [Candidate] {
        guard let position = Position(fen: fen) else { return [] }
        let board = Board(position: position)
        var result: [Candidate] = []
        for piece in position.pieces where piece.color == position.sideToMove {
            for target in board.legalMoves(forPieceAt: piece.square) {
                let base = piece.square.notation + target.notation
                let lastRank = piece.color == .white ? 8 : 1
                let suffixes = piece.kind == .pawn && target.rank.value == lastRank ? ["q", "r", "b", "n"] : [""]
                for suffix in suffixes {
                    guard let applied = Rules.apply(uci: base + suffix, to: fen) else { continue }
                    result.append(Candidate(uci: base + suffix, kind: piece.kind, isCapture: applied.isCapture,
                                            isCastle: applied.isCastle, san: applied.san))
                }
            }
        }
        return result
    }

    /// The UCI move the phrase names on `fen`, or nil when it names none or more than one.
    public static func parse(_ text: String, fen: String) -> String? {
        let words = tokens(text)
        guard !words.isEmpty else { return nil }
        let legal = legalMoves(fen: fen)

        // Castling: "castle", "castles", "castling", "o o" / "o o o".
        let saysCastle = words.contains { $0.hasPrefix("castl") } || words.joined(separator: " ").contains("o o")
        if saysCastle {
            let joined = words.joined(separator: " ")
            let queenside = words.contains { $0.hasPrefix("queen") || $0 == "long" } || joined.contains("o o o")
            let castles = legal.filter(\.isCastle)
            let wanted = castles.first { ($0.san == "O-O-O") == queenside }
            if let move = wanted ?? castles.first { return move.uci }
        }

        let spoken = squares(in: words)
        guard let to = spoken.last else { return nil }
        let from = spoken.count >= 2 ? spoken[spoken.count - 2] : nil

        let promoteAt = words.firstIndex { promoteWords.contains($0) }
        var promotion: Character?
        var piece: Piece.Kind?
        if let promoteAt {
            let after = words[(promoteAt + 1)...].compactMap(pieceWord).first
            switch after {
            case .knight: promotion = "n"
            case .rook: promotion = "r"
            case .bishop: promotion = "b"
            default: promotion = "q"
            }
            piece = .pawn
        } else {
            piece = pieceWords.first { words.contains($0.0) }?.1
        }

        var candidates = legal.filter { String($0.uci.dropFirst(2).prefix(2)) == to }
        if let from { candidates = candidates.filter { $0.uci.hasPrefix(from) } }
        if let piece { candidates = candidates.filter { $0.kind == piece } }
        if words.contains(where: captureWords.contains) {
            let captures = candidates.filter(\.isCapture)
            if !captures.isEmpty { candidates = captures }
        }
        // A promotion defaults to the queen unless another piece was named.
        candidates = candidates.filter { $0.uci.count == 4 || $0.uci.last == (promotion ?? "q") }

        if candidates.count > 1 {
            // "knight b to c4", "b knight c4": a lone file letter other than the target's file.
            let fileHints = words.filter { $0.count == 1 && ("a"..."h").contains($0.first!) }
            if let hint = fileHints.first(where: { $0.first != to.first }) {
                let narrowed = candidates.filter { $0.uci.first == hint.first }
                if !narrowed.isEmpty { candidates = narrowed }
            }
        }
        return candidates.count == 1 ? candidates[0].uci : nil
    }
}
