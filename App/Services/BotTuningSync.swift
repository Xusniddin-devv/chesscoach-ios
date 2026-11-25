import Foundation
import OSLog
import ChessCore

/// Bot strength numbers (`BotTuning`) downloaded from the project's GitHub Pages site, so bots
/// can be retuned without a new build. Only numbers come down, never code: a missing, broken
/// or out-of-range file leaves the last good copy (or the built-in values) in place, and every
/// value is clamped (`BotTuning.sanitized`). A plain GET with no identifiers; at most once a day.
@MainActor
enum BotTuningSync {
    nonisolated static let url = URL(string: "https://xusniddin-devv.github.io/chesscoach-ios/config/bots.json")!
    nonisolated static let cacheKey = "bots.tuning"
    nonisolated static let fetchedAtKey = "bots.tuningFetchedAt"
    nonisolated static let minInterval: TimeInterval = 24 * 3_600

    private static let log = Logger(subsystem: "uz.xq.chessc", category: "bots")

    /// Applies the last downloaded copy, if any. Call before the first bot move.
    static func applyCached(defaults: UserDefaults = .standard) {
        guard let data = defaults.data(forKey: cacheKey),
              let tuning = try? JSONDecoder().decode(BotTuning.self, from: data) else { return }
        BotTuning.current = tuning
    }

    /// Downloads and applies a fresh copy when the last one is older than a day.
    static func refresh(defaults: UserDefaults = .standard, session: URLSession = .shared,
                        now: Date = .now) async {
        if let last = defaults.object(forKey: fetchedAtKey) as? Date,
           now.timeIntervalSince(last) < minInterval { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let tuning = try JSONDecoder().decode(BotTuning.self, from: data).sanitized()
            BotTuning.current = tuning
            defaults.set(try JSONEncoder().encode(tuning), forKey: cacheKey)
            defaults.set(now, forKey: fetchedAtKey)
        } catch {
            log.info("bot tuning not updated: \(error.localizedDescription, privacy: .public)")
        }
    }
}
