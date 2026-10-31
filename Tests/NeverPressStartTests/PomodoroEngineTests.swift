import AppKit
import Testing
@testable import NeverPressStart

/// Lock, sleep and unlock during a break (#21).
@MainActor
struct PomodoroEngineTests {
    private let lock = Notification(name: .init("com.apple.screenIsLocked"))
    private let unlock = Notification(name: .init("com.apple.screenIsUnlocked"))
    private let wake = Notification(name: NSWorkspace.screensDidWakeNotification)

    /// An engine on a break, with a clock the test moves.
    private func onBreak() -> (PomodoroEngine, (TimeInterval) -> Void) {
        let engine = PomodoroEngine()
        var clock = Date(timeIntervalSince1970: 1_000_000)
        engine.now = { clock }
        engine.isAway = { false }
        engine.breakNow()
        return (engine, { clock += $0 })
    }

    private func isOverlay(_ engine: PomodoroEngine) -> Bool {
        if case .overlay = engine.state { return true }
        return false
    }

    @Test func lockedStaysIdleDespiteInput() {
        let engine = PomodoroEngine()
        var locked = false
        engine.isAway = { locked }
        engine.secondsSinceLastInput = { 0 }   // the lock keystroke
        engine.reset()
        locked = true
        engine.away(lock)
        engine.tick()
        #expect(engine.state == .idle)
        locked = false
        engine.tick()
        guard case .working = engine.state else { Issue.record("expected working, got \(engine.state)"); return }
    }

    @Test func sessionAwayState() {
        #expect(!PomodoroEngine.isAway(session: [:]))
        #expect(!PomodoroEngine.isAway(session: [kCGSessionOnConsoleKey as String: true]))
        #expect(PomodoroEngine.isAway(session: ["CGSSessionScreenIsLocked": true, kCGSessionOnConsoleKey as String: true]))
        #expect(PomodoroEngine.isAway(session: [kCGSessionOnConsoleKey as String: false]))
    }

    @Test func shortLockKeepsOverlay() {
        let (engine, advance) = onBreak()
        engine.away(lock)
        advance(engine.idleSeconds - 1)
        engine.back(unlock)
        engine.back(wake)   // duplicate notification right after
        #expect(isOverlay(engine))
    }

    @Test func lockOfIdleLengthEndsBreak() {
        let (engine, advance) = onBreak()
        engine.away(lock)
        engine.away(lock)   // a second away notification must not restart the measurement
        advance(engine.idleSeconds)
        engine.back(unlock)
        guard case .working = engine.state else { Issue.record("expected working, got \(engine.state)"); return }
    }

    @Test func shortSleepKeepsOverlay() {
        let (engine, advance) = onBreak()
        engine.willSleep()
        #expect(isOverlay(engine))
        advance(10)
        engine.back(wake)
        #expect(isOverlay(engine))
    }

    @Test func longSleepEndsBreak() {
        let (engine, advance) = onBreak()
        engine.away(lock)
        engine.willSleep()
        advance(engine.idleSeconds + 60)
        engine.back(wake)
        guard case .working = engine.state else { Issue.record("expected working, got \(engine.state)"); return }
    }

    @Test func oldLockIsNotMeasuredAgain() {
        let (engine, advance) = onBreak()
        engine.away(lock)
        engine.backToWork()          // the state change clears the lock time
        engine.breakNow()
        advance(engine.idleSeconds * 2)
        engine.back(unlock)          // no lock during this break
        #expect(isOverlay(engine))
    }
}

/// A fake calendar: one event whose break comes due at `breakAt` and which runs over `meeting`, each claimed once.
@MainActor
private final class FakeSchedule: MeetingSchedule {
    var breakAt: Date?
    var meeting: Range<Date>?
    private(set) var breakClaimed = false
    private var meetingClaimed = false

    func claimBreak(now: Date) -> Bool {
        guard let breakAt, now >= breakAt, !breakClaimed else { return false }
        breakClaimed = true
        return true
    }

    func claimMeeting(now: Date) -> Date? {
        guard let meeting, meeting.contains(now), !meetingClaimed else { return nil }
        meetingClaimed = true
        return meeting.upperBound
    }
}

/// Breaks before calendar events and snoozing through them.
@MainActor
struct MeetingTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// A working engine at `t0` with active input, the fake schedule and a clock the test moves.
    private func working() -> (PomodoroEngine, FakeSchedule, (TimeInterval) -> Void) {
        let engine = PomodoroEngine()
        let schedule = FakeSchedule()
        var clock = t0
        engine.now = { clock }
        engine.secondsSinceLastInput = { 0 }
        engine.isAway = { false }
        engine.meetings = schedule
        engine.reset()
        return (engine, schedule, { clock += $0 })
    }

    @Test func breakComesUpBeforeMeeting() {
        let (engine, schedule, advance) = working()
        schedule.breakAt = t0 + 60
        engine.tick()
        #expect(engine.state == .working(deadline: t0 + engine.workSeconds))
        advance(60)
        engine.tick()
        #expect(engine.state == .overlay(since: t0 + 60))
    }

    @Test func meetingSnoozesUntilItEndsThenStartsFreshPeriod() {
        let (engine, schedule, advance) = working()
        let end = t0 + 1800
        schedule.meeting = t0 + 60..<end
        advance(60)
        engine.tick()
        #expect(engine.state == .snoozed(until: end))
        advance(1740)
        engine.tick()
        #expect(engine.state == .working(deadline: end + engine.workSeconds))
    }

    @Test func meetingStartingDuringBreakClosesOverlay() {
        let (engine, schedule, advance) = working()
        schedule.breakAt = t0
        schedule.meeting = t0 + 1200..<t0 + 3000
        engine.tick()
        #expect(engine.state == .overlay(since: t0))
        advance(1200)
        engine.tick()
        #expect(engine.state == .snoozed(until: t0 + 3000))
    }

    @Test func meetingWinsOverWorkPeriodEndingAtItsStart() {
        let (engine, schedule, advance) = working()
        engine.backToWork()   // dismissed a break just as the event came within the lead time
        schedule.breakAt = t0
        schedule.meeting = t0 + engine.workSeconds..<t0 + engine.workSeconds + 1800
        engine.tick()
        #expect(engine.state == .working(deadline: t0 + engine.workSeconds))
        advance(engine.workSeconds)
        engine.tick()
        #expect(engine.state == .snoozed(until: t0 + engine.workSeconds + 1800))
    }

    @Test func breakRightAfterAnotherIsSkippedAndHandled() {
        let (engine, schedule, advance) = working()
        engine.backToWork()
        advance(engine.idleSeconds - 1)
        schedule.breakAt = t0
        engine.tick()
        #expect(schedule.breakClaimed)
        advance(engine.idleSeconds)
        engine.tick()
        guard case .working = engine.state else { Issue.record("expected working, got \(engine.state)"); return }
    }

    @Test func lockAndUnlockDoNotSwallowBreak() {
        let (engine, schedule, _) = working()
        schedule.breakAt = t0
        engine.away(Notification(name: .init("com.apple.screenIsLocked")))
        #expect(engine.state == .idle)
        engine.tick()   // input is recent, so idle ends at once, but a lock is no break
        engine.back(Notification(name: .init("com.apple.screenIsUnlocked")))
        #expect(engine.lastBreakEnd == nil)
        engine.tick()
        #expect(engine.state == .overlay(since: t0))
    }

    @Test func pauseKeepsBreakForLater() {
        let (engine, schedule, _) = working()
        engine.togglePause()
        schedule.breakAt = t0
        engine.tick()
        #expect(!schedule.breakClaimed)
        engine.togglePause()
        engine.tick()
        #expect(engine.state == .overlay(since: t0))
    }

    @Test func longSnoozeEndingMidMeetingSnoozesUntilMeetingEnds() {
        let (engine, schedule, advance) = working()
        engine.longSnooze()
        let end = t0 + engine.longSnoozeSeconds + 1800
        schedule.breakAt = t0 + 60
        schedule.meeting = t0 + 600..<end
        advance(600)
        engine.tick()
        #expect(engine.state == .snoozed(until: t0 + engine.longSnoozeSeconds))
        advance(engine.longSnoozeSeconds - 600)
        engine.tick()   // long snooze finished
        engine.tick()
        #expect(engine.state == .snoozed(until: end))
    }

    @Test func resumeEndsMeetingSnoozeForGood() {
        let (engine, schedule, advance) = working()
        schedule.meeting = t0..<t0 + 1800
        engine.tick()
        #expect(engine.state == .snoozed(until: t0 + 1800))
        advance(60)
        engine.togglePause()
        engine.tick()
        #expect(engine.state == .working(deadline: t0 + 60 + engine.workSeconds))
    }
}
