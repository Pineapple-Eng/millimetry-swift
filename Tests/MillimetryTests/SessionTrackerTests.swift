import Foundation
import Testing
@testable import Millimetry

struct SessionTrackerTests {
    let start = Date(timeIntervalSince1970: 1_791_000_000)

    @Test func theFirstEventStartsASessionAndLaterEventsShareIt() {
        var tracker = SessionTracker(timeout: 1_800)
        #expect(tracker.current == nil)
        let first = tracker.sessionID(at: start)
        #expect(tracker.sessionID(at: start + 60) == first)
        #expect(tracker.sessionID(at: start + 60 + 1_799) == first, "each event extends the session")
    }

    @Test(arguments: [(1_799.0, false), (1_800.0, true), (7_200.0, true)])
    func thirtyMinutesWithoutEventsEndsTheSession(gap: TimeInterval, rotates: Bool) {
        var tracker = SessionTracker(timeout: 1_800)
        let first = tracker.sessionID(at: start)
        let next = tracker.sessionID(at: start + gap)
        #expect((next != first) == rotates)
    }

    @Test(arguments: [(600.0, false), (1_800.0, true), (86_400.0, true)])
    func thirtyMinutesInTheBackgroundEndsTheSession(away: TimeInterval, rotates: Bool) {
        var tracker = SessionTracker(timeout: 1_800)
        let first = tracker.sessionID(at: start)
        tracker.enterBackground(at: start + 10)
        tracker.enterForeground(at: start + 10 + away)
        // An event right after returning: within the idle limit only if the background was short.
        let next = tracker.sessionID(at: start + 10 + away)
        #expect((next != first) == rotates)
    }

    @Test func aShortTripToTheBackgroundKeepsTheSessionEvenPastTheIdleWindowStart() {
        var tracker = SessionTracker(timeout: 1_800)
        let first = tracker.sessionID(at: start)
        tracker.enterBackground(at: start + 1_000)
        tracker.enterForeground(at: start + 1_500)
        #expect(tracker.sessionID(at: start + 1_600) == first)
    }

    @Test func sessionsAreNeverReusedAcrossLaunches() {
        var firstLaunch = SessionTracker(timeout: 1_800)
        var secondLaunch = SessionTracker(timeout: 1_800)
        #expect(firstLaunch.sessionID(at: start) != secondLaunch.sessionID(at: start))
    }

    @Test func sessionIdsAreVersionSevenWithTheStartTime() {
        var tracker = SessionTracker(timeout: 1_800)
        let id = tracker.sessionID(at: start)
        #expect(UUIDv7.milliseconds(of: id) == UInt64(start.timeIntervalSince1970 * 1_000))
    }
}
