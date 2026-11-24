import Foundation

/// One PGN game: its tag pairs and its mainline SAN moves (comments, variations, NAGs,
/// move numbers and the result token removed).
public struct PGNGame: Sendable, Equatable {
    public var tags: [String: String]
    public var sans: [String]

    public init(tags: [String: String], sans: [String]) {
        self.tags = tags
        self.sans = sans
    }

    /// Parses the first game in `text`. Nil when there is no movetext and no tags.
    public static func parse(_ text: String) -> PGNGame? {
        var tags: [String: String] = [:]
        var movetext = ""
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]"), let space = line.firstIndex(of: " ") {
                let key = String(line[line.index(after: line.startIndex)..<space])
                var value = line[line.index(after: space)..<line.index(before: line.endIndex)]
                    .trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                    value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
                }
                tags[key] = value
            } else {
                movetext += line + " "
            }
        }
        let sans = tokens(movetext)
        if tags.isEmpty && sans.isEmpty { return nil }
        return PGNGame(tags: tags, sans: sans)
    }

    /// Mainline SAN tokens of a movetext.
    static func tokens(_ movetext: String) -> [String] {
        var out: [String] = []
        var depth = 0          // variation nesting
        var inComment = false  // { … }
        var current = ""

        func flush() {
            defer { current = "" }
            var token = current
            guard !token.isEmpty, depth == 0 else { return }
            // "12." / "12..." prefixes, sometimes glued to the move ("12.e4").
            if let range = token.range(of: #"^\d+\.+"#, options: .regularExpression) {
                token.removeSubrange(range)
            }
            guard !token.isEmpty, !token.hasPrefix("$"),
                  !["1-0", "0-1", "1/2-1/2", "½-½", "*"].contains(token) else { return }
            out.append(token)
        }

        var skipLine = false   // ";" comment to end of line (already joined, so to the end)
        for ch in movetext {
            if skipLine { continue }
            if inComment { if ch == "}" { inComment = false }; continue }
            switch ch {
            case "{": flush(); inComment = true
            case "(": flush(); depth += 1
            case ")": flush(); depth = max(0, depth - 1)
            case ";": flush(); skipLine = true
            case " ", "\t", "\n", "\r": flush()
            default: current.append(ch)
            }
        }
        flush()
        return out
    }
}

/// Turns platform PGNs into stored games.
public enum PGNImporter {
    public enum Failure: Error, Equatable {
        /// The username plays neither side.
        case notUsersGame
        /// A move does not parse or is illegal (non-standard start, corrupt PGN).
        case illegalMove(ply: Int, san: String)
    }

    /// A `GameSnapshot` from one PGN: the user's colour by username (case-insensitive),
    /// `source` set, opponent name and rating from the tags, the user's rating in
    /// `playerRatingUsed`. Silent mode, no verdicts: analysis comes later.
    public static func snapshot(pgn: String, username: String, platform: ImportPlatform,
                                fallbackDate: Date = .now) throws -> GameSnapshot {
        guard let game = PGNGame.parse(pgn) else { throw Failure.illegalMove(ply: 0, san: "") }
        let me = username.lowercased()
        let white = game.tags["White"] ?? ""
        let black = game.tags["Black"] ?? ""
        let userColor: Piece.Color
        if white.lowercased() == me { userColor = .white }
        else if black.lowercased() == me { userColor = .black }
        else { throw Failure.notUsersGame }

        let startFen = (game.tags["SetUp"] == "1" ? game.tags["FEN"] : nil) ?? Rules.startFen
        var fen = startFen
        var moves: [String] = []
        var sans: [String] = []
        for (i, san) in game.sans.enumerated() {
            guard let uci = uci(san: san, fen: fen), let applied = Rules.apply(uci: uci, to: fen) else {
                throw Failure.illegalMove(ply: i + 1, san: san)
            }
            moves.append(uci)
            sans.append(applied.san)
            fen = applied.fenAfter
        }

        let result = GameResult(rawValue: game.tags["Result"] ?? "*") ?? .ongoing
        let opponentKey = userColor == .white ? "Black" : "White"
        let myElo = Int(game.tags[userColor == .white ? "WhiteElo" : "BlackElo"] ?? "")
        let site = game.tags["Link"] ?? game.tags["Site"]
        return GameSnapshot(
            id: stableId(platform: platform, key: site ?? pgn),
            date: date(game.tags) ?? fallbackDate,
            botId: platform.rawValue, userColor: userColor, mode: .silent, startFen: startFen,
            moves: moves, sans: sans, result: result, verdicts: [], analysisVersion: 1,
            playerRatingUsed: myElo ?? PlayerProfile.defaultRating,
            source: platform.rawValue,
            opponentName: game.tags[opponentKey],
            opponentRating: Int(game.tags[opponentKey + "Elo"] ?? ""),
            externalURL: site.flatMap { $0.hasPrefix("http") ? $0 : nil })
    }

    /// `snapshot(pgn:)` plus what the platform already knew: its accuracies, and a quick
    /// analysis from its per-ply evals when they cover every ply (source marked).
    public static func snapshot(game: ImportedGame, username: String, platform: ImportPlatform,
                                fallbackDate: Date = .now) throws -> GameSnapshot {
        var s = try snapshot(pgn: game.pgn, username: username, platform: platform, fallbackDate: fallbackDate)
        s.platformAccuracy = game.accuracy
        if let evals = game.evals {
            s.analysis = PlatformEvals.analysis(startFen: s.startFen, moves: s.moves, evals: evals, source: platform.rawValue)
        }
        return s
    }

    /// The legal move written `san`: only moves to the SAN's destination square are tried.
    static func uci(san: String, fen: String) -> String? {
        let clean = san.filter { !"+#!?".contains($0) }.replacingOccurrences(of: "0-0", with: "O-O")
        let legal = Rules.legalMoves(fen: fen)
        let candidates: [String]
        if clean.hasPrefix("O-O") {
            candidates = legal.filter { Rules.piece(at: Square(String($0.prefix(2))), fen: fen)?.kind == .king }
        } else {
            // Destination = the last square-shaped pair, before any "=Q" promotion suffix.
            let base = clean.split(separator: "=").first.map(String.init) ?? clean
            let dest = String(base.suffix(2))
            candidates = legal.filter { $0.dropFirst(2).prefix(2) == dest }
        }
        return candidates.first { uci in
            Rules.apply(uci: uci, to: fen).map {
                $0.san.filter { !"+#!?".contains($0) } == clean
            } ?? false
        }
    }

    /// UTCDate + UTCTime (both platforms), else Date.
    static func date(_ tags: [String: String]) -> Date? {
        let day = tags["UTCDate"] ?? tags["Date"]
        guard let day, !day.contains("?") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        if let time = tags["UTCTime"] {
            formatter.dateFormat = "yyyy.MM.dd HH:mm:ss"
            if let d = formatter.date(from: "\(day) \(time)") { return d }
        }
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.date(from: day)
    }

    /// The same platform game always gets the same id, so a re-import replaces instead of duplicating.
    static func stableId(platform: ImportPlatform, key: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        // Two FNV-1a passes with different seeds → 128 bits.
        var a: UInt64 = 0xcbf29ce484222325
        var b: UInt64 = 0x84222325cbf29ce4
        for byte in (platform.rawValue + ":" + key).utf8 {
            a = (a ^ UInt64(byte)) &* 0x100000001b3
            b = (b ^ UInt64(byte)) &* 0x100000001b3 &+ 0x9e3779b97f4a7c15
        }
        for i in 0..<8 { bytes[i] = UInt8((a >> (8 * UInt64(i))) & 0xff); bytes[8 + i] = UInt8((b >> (8 * UInt64(i))) & 0xff) }
        bytes[6] = (bytes[6] & 0x0f) | 0x50  // version 5-style
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
