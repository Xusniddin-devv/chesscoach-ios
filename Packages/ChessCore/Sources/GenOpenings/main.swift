import ChessCore
import Foundation

// Usage: GenOpenings <dir with a.tsv...e.tsv> <output.json>
// Replays every line of the lichess chess-openings TSVs (eco, name, pgn) and writes
// [{"key": "<FEN fields 1-4>", "eco", "name"}], keeping the longest line per position.

struct Entry: Codable {
    var key: String
    var eco: String
    var name: String
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 3 else { fail("usage: GenOpenings <tsv-dir> <output.json>") }
let dir = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[2])

func key(_ fen: String) -> String {
    fen.split(separator: " ").prefix(4).joined(separator: " ")
}

func sanTokens(_ pgn: String) -> [String] {
    pgn.split(separator: " ").map(String.init).filter { token in
        !(token.hasSuffix(".") || token.contains("...")) && !token.isEmpty
    }.map { token in
        // Strip a leading move number glued to the move, e.g. "1.e4".
        if let dot = token.firstIndex(of: "."), token.first?.isNumber == true {
            return String(token[token.index(after: dot)...])
        }
        return token
    }
}

var best: [String: (entry: Entry, plies: Int)] = [:]
var lines = 0

for letter in ["a", "b", "c", "d", "e"] {
    let url = dir.appendingPathComponent("\(letter).tsv")
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { fail("cannot read \(url.path)") }
    for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
        let cols = raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        if index == 0 && cols.first == "eco" { continue }
        guard cols.count >= 3 else { fail("\(letter).tsv:\(index + 1): expected 3 columns") }
        var fen = Rules.startFen
        let moves = sanTokens(cols[2])
        guard !moves.isEmpty else { fail("\(letter).tsv:\(index + 1): empty pgn") }
        for san in moves {
            guard let position = Position(fen: fen),
                  let move = Move(san: san, position: position),
                  let applied = Rules.apply(uci: move.lan, to: fen) else {
                fail("\(letter).tsv:\(index + 1): cannot replay '\(san)' in \(cols[2])")
            }
            fen = applied.fenAfter
        }
        lines += 1
        let candidate = Entry(key: key(fen), eco: cols[0], name: cols[1])
        if let current = best[candidate.key] {
            let wins = moves.count > current.plies
                || (moves.count == current.plies
                    && (candidate.eco, candidate.name) < (current.entry.eco, current.entry.name))
            if !wins { continue }
        }
        best[candidate.key] = (candidate, moves.count)
    }
}

let entries = best.values.map(\.entry).sorted { $0.key < $1.key }
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
do {
    try encoder.encode(entries).write(to: out)
} catch {
    fail("write failed: \(error)")
}
print("replayed \(lines) lines, wrote \(entries.count) positions to \(out.path)")
