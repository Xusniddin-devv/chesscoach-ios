import Foundation

public enum LessonTrack: String, Codable, Sendable, CaseIterable {
    case openings, endgames, checkmates

    public var title: String {
        switch self {
        case .openings: "Openings"
        case .endgames: "Endgames"
        case .checkmates: "Checkmate patterns"
        }
    }
}

/// What finishing a lesson means.
public enum LessonGoal: String, Codable, Sendable {
    /// Play the scripted line (openings): the user's moves are checked, the other side's are played.
    case line
    /// Find the mating move (checkmate patterns): any checkmate counts.
    case mate
    /// Free play against the engine until checkmate (endgames).
    case win
    /// Free play against the engine until the game is drawn (endgames).
    case draw
}

public enum LessonSide: String, Sendable {
    case user, auto
}

public struct LessonStep: Sendable, Equatable {
    public var uci: String
    public var san: String
    public var side: LessonSide
    public var explanation: String
}

/// A Learn lesson: 12 openings, 12 endgames, 10 checkmate patterns, ported from the web
/// app (openings.ts, endgames.ts, checkmates.ts) into Resources/lessons.json.
public struct Lesson: Sendable, Equatable, Identifiable {
    public var id: String
    public var track: LessonTrack
    public var title: String
    public var summary: String
    public var startFen: String
    public var userColor: Piece.Color
    public var goal: LessonGoal
    /// Scripted moves in order; empty for free-play endgames.
    public var steps: [LessonStep]
}

public enum LessonLibrary {
    public static let all: [Lesson] = {
        guard let url = Bundle.module.url(forResource: "lessons", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([Row].self, from: data) else {
            assertionFailure("LessonLibrary: lessons.json missing or undecodable")
            return []
        }
        return rows.compactMap(\.lesson)
    }()

    public static func lessons(in track: LessonTrack) -> [Lesson] { all.filter { $0.track == track } }

    public static func lesson(id: String) -> Lesson? { all.first { $0.id == id } }

    /// Number of rows in lessons.json, resolvable or not (tests compare it with `all`).
    static var rowCount: Int {
        guard let url = Bundle.module.url(forResource: "lessons", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([Row].self, from: data) else { return 0 }
        return rows.count
    }

    struct Row: Decodable {
        struct Step: Decodable {
            var san: String?
            var uci: String?
            var note: String
        }
        var id: String
        var track: LessonTrack
        var title: String
        var summary: String
        var startFen: String
        var userColor: String
        var goal: LessonGoal
        var steps: [Step]

        /// Resolves SAN to UCI move by move; nil if any step is illegal.
        var lesson: Lesson? {
            let user: Piece.Color = userColor == "b" ? .black : .white
            var fen = startFen
            var resolved: [LessonStep] = []
            for step in steps {
                guard let uci = step.uci ?? step.san.flatMap({ Rules.uci(san: $0, fen: fen) }),
                      let applied = Rules.apply(uci: uci, to: fen) else { return nil }
                let mover: Piece.Color = fen.split(separator: " ").dropFirst().first == "b" ? .black : .white
                resolved.append(LessonStep(uci: uci, san: applied.san, side: mover == user ? .user : .auto,
                                           explanation: step.note))
                fen = applied.fenAfter
            }
            return Lesson(id: id, track: track, title: title, summary: summary, startFen: startFen,
                          userColor: user, goal: goal, steps: resolved)
        }
    }
}
