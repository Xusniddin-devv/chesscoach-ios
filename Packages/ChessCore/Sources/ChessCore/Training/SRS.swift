import Foundation

/// SM-2-lite spaced repetition for puzzle scheduling (port of the web app's `srs.ts`).
public struct SRSState: Codable, Sendable, Equatable {
    public var intervalDays: Double
    public var ease: Double
    public var reps: Int
    public var lapses: Int

    public init(intervalDays: Double, ease: Double, reps: Int, lapses: Int) {
        self.intervalDays = intervalDays
        self.ease = ease
        self.reps = reps
        self.lapses = lapses
    }

    public static let new = SRSState(intervalDays: 0, ease: 2.5, reps: 0, lapses: 0)
}

public struct SRSReview: Sendable, Equatable {
    public var state: SRSState
    public var due: Date
}

public enum SRS {
    public static let minEase = 1.3
    public static let failRetryMinutes = 10.0

    public static func review(_ state: SRSState, success: Bool, now: Date) -> SRSReview {
        guard success else {
            let failed = SRSState(intervalDays: 0, ease: max(minEase, state.ease - 0.2),
                                  reps: 0, lapses: state.lapses + 1)
            return SRSReview(state: failed, due: now.addingTimeInterval(failRetryMinutes * 60))
        }
        let reps = state.reps + 1
        let interval: Double = switch reps {
        case 1: 1
        case 2: 3
        default: (state.intervalDays * state.ease * 10).rounded(.toNearestOrAwayFromZero) / 10
        }
        let next = SRSState(intervalDays: interval, ease: state.ease, reps: reps, lapses: state.lapses)
        return SRSReview(state: next, due: now.addingTimeInterval(interval * 86_400))
    }
}
