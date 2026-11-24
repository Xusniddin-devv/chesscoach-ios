import ChessCore

/// Parses the two Stockfish output lines the engine actor needs.
enum UCIParser {
    /// A scored `info` line (`multipv` defaults to 1, `pv` may be empty); nil for lines
    /// without a depth and a score, such as `currmove` progress or `info string`.
    static func info(_ line: String) -> PVLine? {
        let tokens = line.split(separator: " ").map(String.init)
        guard tokens.first == "info" else { return nil }
        var depth: Int?, multipv = 1, score: Score?, pv: [String] = []
        var i = 1
        while i < tokens.count {
            let next = i + 1 < tokens.count ? tokens[i + 1] : nil
            switch tokens[i] {
            case "depth": depth = next.flatMap { Int($0) }
            case "multipv": multipv = next.flatMap { Int($0) } ?? 1
            case "score":
                let value = i + 2 < tokens.count ? Int(tokens[i + 2]) : nil
                if next == "cp" { score = Score(cp: value) }
                if next == "mate" { score = Score(mate: value) }
            case "pv":
                pv = Array(tokens[(i + 1)...])
                i = tokens.count
            default: break
            }
            i += 1
        }
        guard let depth, let score, score.cp != nil || score.mate != nil else { return nil }
        return PVLine(multipv: multipv, depth: depth, score: score, pv: pv)
    }

    /// The move of a `bestmove` line, "" for `bestmove (none)`; nil for any other line.
    static func bestMove(_ line: String) -> String? {
        let tokens = line.split(separator: " ")
        guard tokens.first == "bestmove", tokens.count >= 2 else { return nil }
        return tokens[1] == "(none)" ? "" : String(tokens[1])
    }
}
