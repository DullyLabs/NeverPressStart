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
        engine.breakNow()
        return (engine, { clock += $0 })
    }

    private func isOverlay(_ engine: PomodoroEngine) -> Bool {
        if case .overlay = engine.state { return true }
        return false
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
