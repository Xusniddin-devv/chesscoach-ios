import Foundation

/// Daily activity streak, counted in calendar days of the given calendar (the user's local
/// days in the app). Pure: callers store the state and pass `now` and the calendar in.
public struct Streak: Codable, Sendable, Equatable {
    public var count: Int
    /// Start of the last day with activity; nil before the first activity.
    public var lastDay: Date?

    public init(count: Int = 0, lastDay: Date? = nil) {
        self.count = count
        self.lastDay = lastDay
    }

    /// Records activity at `now`: same day keeps the count, the next day advances it,
    /// a gap of a day or more starts over at 1.
    public func recordingActivity(now: Date, calendar: Calendar = .current) -> Streak {
        let today = calendar.startOfDay(for: now)
        guard let last = lastDay else { return Streak(count: 1, lastDay: today) }
        switch Self.days(from: last, to: today, calendar: calendar) {
        case ...0: return Streak(count: max(count, 1), lastDay: max(last, today))
        case 1: return Streak(count: count + 1, lastDay: today)
        default: return Streak(count: 1, lastDay: today)
        }
    }

    /// The streak as shown at `now`: still alive today and yesterday, 0 once a day is missed.
    public func current(now: Date, calendar: Calendar = .current) -> Int {
        guard let last = lastDay else { return 0 }
        let gap = Self.days(from: last, to: calendar.startOfDay(for: now), calendar: calendar)
        return gap <= 1 ? count : 0
    }

    /// True when activity was already recorded on the day of `now`.
    public func isActive(on now: Date, calendar: Calendar = .current) -> Bool {
        guard let last = lastDay else { return false }
        return calendar.isDate(last, inSameDayAs: now)
    }

    private static func days(from a: Date, to b: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }
}
