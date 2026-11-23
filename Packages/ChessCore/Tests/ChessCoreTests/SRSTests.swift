import Foundation
import Testing
@testable import ChessCore

private let now = Date(timeIntervalSince1970: 1_781_136_000) // 2026-06-11T00:00:00Z

@Test func srsProgressesOneThreeThenIntervalTimesEase() {
    let r1 = SRS.review(.new, success: true, now: now)
    #expect(r1.state.intervalDays == 1)
    #expect(r1.state.reps == 1)
    let r2 = SRS.review(r1.state, success: true, now: now)
    #expect(r2.state.intervalDays == 3)
    let r3 = SRS.review(r2.state, success: true, now: now)
    #expect(abs(r3.state.intervalDays - 7.5) < 1e-9)
    #expect(r3.due == now.addingTimeInterval(7.5 * 86_400))
}

@Test func srsFailureResetsRepsLowersEaseRetriesInTenMinutes() {
    let learned = SRS.review(SRS.review(.new, success: true, now: now).state, success: true, now: now).state
    let failed = SRS.review(learned, success: false, now: now)
    #expect(failed.state.reps == 0)
    #expect(failed.state.lapses == 1)
    #expect(failed.state.intervalDays == 0)
    #expect(abs(failed.state.ease - 2.3) < 1e-9)
    #expect(failed.due == now.addingTimeInterval(600))
}

@Test func srsEaseNeverDropsBelowMinimum() {
    var s = SRSState(intervalDays: 0, ease: 1.35, reps: 0, lapses: 0)
    s = SRS.review(s, success: false, now: now).state
    #expect(s.ease == 1.3)
    s = SRS.review(s, success: false, now: now).state
    #expect(s.ease == 1.3)
}

@Test func srsIntervalRoundsToOneDecimal() {
    let s = SRSState(intervalDays: 7.5, ease: 2.3, reps: 3, lapses: 1)
    #expect(SRS.review(s, success: true, now: now).state.intervalDays == 17.3) // 17.25 → 17.3
}
