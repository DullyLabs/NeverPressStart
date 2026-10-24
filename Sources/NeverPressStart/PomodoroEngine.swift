import AppKit
import CoreGraphics

private let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)

func log(_ message: String) {
    let line = "[\(Date().formatted(timestampStyle))] \(message)\n"
    FileHandle.standardError.write(Data(line.utf8))
}

/// Calendar events the engine plans breaks around. Each event is claimed once, so it never triggers twice.
@MainActor
protocol MeetingSchedule: AnyObject {
    /// True once per event as it comes within the lead time; marks every event in that window handled.
    func claimBreak(now: Date) -> Bool
    /// The latest end among events in progress and not yet claimed, which it marks handled.
    func claimMeeting(now: Date) -> Date?
}

/// Work timer state machine: working -> overlay -> working.
/// Idle, sleep and screen lock count as a break taken and reset the timer.
@MainActor
final class PomodoroEngine: NSObject {
    enum State: Equatable {
        case working(deadline: Date)
        case paused(remaining: TimeInterval)
        case idle                   // user away; waiting for input to start a fresh period
        case snoozed(until: Date)   // long snooze for calls/presentations; no idle or overlay
        case asleep                 // system sleeping; frozen until wake, so no overlay flash on wake
        case overlay(since: Date)
    }

    // Read at use time so Settings changes apply from the next period.
    var workSeconds: TimeInterval { Setting.work.seconds }
    var snoozeSeconds: TimeInterval { Setting.snooze.seconds }
    var idleSeconds: TimeInterval { Setting.idle.seconds }
    var longSnoozeSeconds: TimeInterval { Setting.longSnooze.seconds }

    private(set) var state: State = .paused(remaining: 0)
    var onStateChange: ((State) -> Void)?
    var onTick: (() -> Void)?
    var meetings: MeetingSchedule?
    /// When the last break was dismissed or idle ended, so a meeting break right after one is skipped.
    private(set) var lastBreakEnd: Date?
    /// The idle state came from no input (a real break), not a lock or screen sleep.
    private var idleIsBreak = false
    /// The snooze is for a calendar event, not the user's long snooze.
    private var snoozedForMeeting = false
    private var timer: Timer?
    private var lastWakeReset = Date.distantPast
    /// When a lock or sleep began during the break; only an away period of at least `idleSeconds` ends it.
    private var awaySince: Date?
    var now: () -> Date = Date.init
    var secondsSinceLastInput: () -> TimeInterval = PomodoroEngine.systemSecondsSinceLastInput
    var isAway: () -> Bool = PomodoroEngine.systemIsAway

    func start() {
        log("config work=\(Int(workSeconds))s snooze=\(Int(snoozeSeconds))s idle=\(Int(idleSeconds))s longSnooze=\(Int(longSnoozeSeconds))s")
        startWork(workSeconds, reason: "launch")

        let t = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)   // keep ticking while the menu is open
        timer = t

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(away(_:)), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(away(_:)), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        ws.addObserver(self, selector: #selector(back(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(back(_:)), name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(back(_:)), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(away(_:)), name: .init("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(back(_:)), name: .init("com.apple.screenIsUnlocked"), object: nil)
    }

    // MARK: - User actions

    func togglePause() {
        switch state {
        case .working(let deadline):
            transition(to: .paused(remaining: max(0, deadline.timeIntervalSince(now()))), reason: "paused by user")
        case .paused(let remaining):
            startWork(remaining > 0 ? remaining : workSeconds, reason: "resumed by user")
        case .snoozed:
            startWork(workSeconds, reason: "long snooze ended by user")
        case .idle, .overlay, .asleep:
            break
        }
    }

    func reset() { startWork(workSeconds, reason: "reset by user") }
    func breakNow() { transition(to: .overlay(since: now()), reason: "break requested by user") }
    func backToWork() {
        lastBreakEnd = now()
        startWork(workSeconds, reason: "overlay dismissed")
    }
    func snooze() {
        lastBreakEnd = now()
        startWork(snoozeSeconds, reason: "snoozed")
    }
    func longSnooze() {
        snoozedForMeeting = false
        transition(to: .snoozed(until: now().addingTimeInterval(longSnoozeSeconds)),
                   reason: "long snooze by user (\(Int(longSnoozeSeconds))s)")
    }

    // MARK: - Internals

    private func startWork(_ seconds: TimeInterval, reason: String) {
        transition(to: .working(deadline: now().addingTimeInterval(seconds)), reason: "\(reason) (\(Int(seconds))s)")
    }

    private func transition(to newState: State, reason: String) {
        guard newState != state else { return }
        log("\(Self.name(of: state)) -> \(Self.name(of: newState)): \(reason)")
        awaySince = nil
        state = newState
        onStateChange?(newState)
    }

    @objc func tick() {
        let before = state
        let now = now()
        switch state {
        case .working(let deadline):
            let idle = secondsSinceLastInput()
            if isAway() {
                idleIsBreak = false
                transition(to: .idle, reason: "screen locked")
            } else if let end = meetings?.claimMeeting(now: now) {
                snoozedForMeeting = true
                transition(to: .snoozed(until: end), reason: "meeting until \(end.formatted(date: .omitted, time: .shortened))")
            } else if meetings?.claimBreak(now: now) == true {
                if now.timeIntervalSince(lastBreakEnd ?? .distantPast) < idleSeconds {
                    log("meeting break skipped, just had one")
                } else {
                    transition(to: .overlay(since: now), reason: "break before meeting")
                }
            } else if idle >= idleSeconds {
                idleIsBreak = true
                transition(to: .idle, reason: "no input for \(Int(idle))s, counting as a break")
            } else if deadline <= now {
                transition(to: .overlay(since: now), reason: "work period finished")
            }
        case .overlay:
            if let end = meetings?.claimMeeting(now: now) {
                snoozedForMeeting = true
                transition(to: .snoozed(until: end), reason: "meeting until \(end.formatted(date: .omitted, time: .shortened))")
            } else {
                _ = meetings?.claimBreak(now: now)   // events coming up during the break count as having had it
            }
        case .idle:
            if !isAway() && secondsSinceLastInput() < idleSeconds {
                if idleIsBreak { lastBreakEnd = now }
                startWork(workSeconds, reason: "input resumed after idle")
            }
        case .snoozed(let until):
            if until <= now {
                startWork(workSeconds, reason: snoozedForMeeting ? "meeting finished" : "long snooze finished")
            }
        case .paused, .asleep:
            break
        }
        if state == before { onTick?() }   // a transition already triggered onStateChange
    }

    @objc func away(_ note: Notification) {
        switch state {
        case .working:
            idleIsBreak = false
            transition(to: .idle, reason: note.name.rawValue)
        case .overlay: awaySince = awaySince ?? now()   // once per away period; lock, screen sleep and session resign arrive together
        default: break
        }
    }

    @objc func willSleep() {
        switch state {
        case .paused, .snoozed: break         // keep a manual pause or long snooze as is
        case .overlay: awaySince = awaySince ?? now()   // a short sleep must not skip the break
        default: transition(to: .asleep, reason: "system going to sleep")
        }
    }

    @objc func back(_ note: Notification) {
        switch state {
        case .paused, .snoozed: return        // respect a manual pause or long snooze
        case .working where now().timeIntervalSince(lastWakeReset) < 2:
            return                            // wake and screen wake (or unlock and session active) arrive together
        case .overlay:
            // Nil for the duplicate notifications that follow, so they keep the overlay too.
            guard let since = awaySince else { return }
            awaySince = nil
            let away = now().timeIntervalSince(since)
            guard away >= idleSeconds else { return log("overlay kept: away \(Int(away))s, under idle \(Int(idleSeconds))s") }
        default: break
        }
        startWork(workSeconds, reason: note.name.rawValue)
        lastWakeReset = now()
    }

    /// kCGAnyInputEventType from the HID system state; readable without any TCC permission.
    static func systemSecondsSinceLastInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// The screen is locked or another user is on the console. The lock key is undocumented; absent means unlocked.
    static func systemIsAway() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool == true
            || session[kCGSessionOnConsoleKey as String] as? Bool == false
    }

    private static func name(of state: State) -> String {
        switch state {
        case .working: return "working"
        case .paused: return "paused"
        case .idle: return "idle"
        case .snoozed: return "snoozed"
        case .asleep: return "asleep"
        case .overlay: return "overlay"
        }
    }
}
