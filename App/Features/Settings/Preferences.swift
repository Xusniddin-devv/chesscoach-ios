import Foundation
import ChessCore

/// UserDefaults keys and defaults for the Settings screen. Views read them with
/// `@AppStorage(Pref.sound) var sound = Pref.Default.sound`; services read `Pref.bool(_:)`.
enum Pref {
    static let sound = "pref.sound"
    static let haptics = "pref.haptics"
    static let voice = "pref.voiceMoves"
    static let coordinates = "pref.boardCoordinates"
    static let wording = "pref.moveWording"
    static let defaultMode = "pref.defaultMode"
    /// Set when onboarding finishes (or is skipped); Reset all data clears it.
    static let hasOnboarded = "hasOnboarded"
    /// The player's puzzle rating (Elo from first outcomes).
    static let puzzleRating = "puzzles.elo"

    enum Default {
        static let sound = true
        static let haptics = true
        static let voice = true
        static let coordinates = true
        static let wording = Wording.words
        static let defaultMode = PlayMode.training
    }

    /// "Show moves as" (spec: Words below ~1200, the default for beginners).
    enum Wording: String, CaseIterable {
        case words, notation

        var title: String { self == .words ? "Words" : "Notation" }
        var moveWording: MoveWording { self == .words ? .words : .notation }
    }

    static var all: [String] { [sound, haptics, voice, coordinates, wording, defaultMode, hasOnboarded, "puzzles.rating", puzzleRating, "learn.track"] }

    /// A Bool preference with its default when never set.
    static func bool(_ key: String, default value: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }

    static var wordingValue: Wording {
        UserDefaults.standard.string(forKey: wording).flatMap(Wording.init) ?? Default.wording
    }

    /// The wording the player chose in Settings, nil while they never changed it (then the
    /// level decides: `EngineHub.wording`).
    static var explicitWording: Wording? {
        UserDefaults.standard.string(forKey: wording).flatMap(Wording.init)
    }

    static var defaultModeValue: PlayMode {
        UserDefaults.standard.string(forKey: defaultMode).flatMap(PlayMode.init) ?? Default.defaultMode
    }
}

enum AppInfo {
    /// The app's public GPLv3 source. PLACEHOLDER until the public repo exists.
    static let sourceURL = URL(string: "https://github.com/Xusniddin-devv/chesscoach-ios")!
    /// PLACEHOLDER pages until the owner publishes real ones.
    static let termsURL = URL(string: "https://xq-chesscoach.netlify.app/terms")!
    static let privacyURL = URL(string: "https://xq-chesscoach.netlify.app/privacy")!

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
