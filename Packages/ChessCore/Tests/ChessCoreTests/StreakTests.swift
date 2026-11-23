import Foundation
import Testing
@testable import ChessCore

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func day(_ d: Int, hour: Int = 12) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
}

@Test func streakStartsAtOneAndHoldsWithinADay() {
    let s = Streak().recordingActivity(now: day(10, hour: 8), calendar: utc)
    #expect(s.count == 1)
    let again = s.recordingActivity(now: day(10, hour: 23), calendar: utc)
    #expect(again.count == 1)
    #expect(again.isActive(on: day(10), calendar: utc))
}

@Test func streakAdvancesOnConsecutiveDays() {
    var s = Streak()
    for d in 10...14 { s = s.recordingActivity(now: day(d), calendar: utc) }
    #expect(s.count == 5)
    #expect(s.current(now: day(14), calendar: utc) == 5)
    // Still alive the next day before any activity.
    #expect(s.current(now: day(15, hour: 22), calendar: utc) == 5)
    #expect(!s.isActive(on: day(15), calendar: utc))
}

@Test func missedDayResetsStreak() {
    var s = Streak()
    for d in 10...12 { s = s.recordingActivity(now: day(d), calendar: utc) }
    #expect(s.current(now: day(14), calendar: utc) == 0)
    s = s.recordingActivity(now: day(14), calendar: utc)
    #expect(s.count == 1)
}

@Test func streakAcrossMidnightCountsAsNextDay() {
    var s = Streak().recordingActivity(now: day(10, hour: 23), calendar: utc)
    s = s.recordingActivity(now: day(11, hour: 0), calendar: utc)
    #expect(s.count == 2)
}

@Test func emptyStreakIsZero() {
    #expect(Streak().current(now: day(10), calendar: utc) == 0)
}
