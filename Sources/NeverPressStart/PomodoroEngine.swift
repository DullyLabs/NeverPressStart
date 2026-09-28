import AppKit
import CoreGraphics

private let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)

func log(_ message: String) {
    let line = "[\(Date().formatted(timestampStyle))] \(message)\n"
    FileHandle.standardError.write(Data(line.utf8))
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
    private var timer: Timer?
    private var lastWakeReset = Date.distantPast

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
            transition(to: .paused(remaining: max(0, deadline.timeIntervalSinceNow)), reason: "paused by user")
        case .paused(let remaining):
            startWork(remaining > 0 ? remaining : workSeconds, reason: "resumed by user")
        case .snoozed:
            startWork(workSeconds, reason: "long snooze ended by user")
        case .idle, .overlay, .asleep:
            break
        }
    }

    func reset() { startWork(workSeconds, reason: "reset by user") }
    func breakNow() { transition(to: .overlay(since: Date()), reason: "break requested by user") }
    func backToWork() { startWork(workSeconds, reason: "overlay dismissed") }
    func snooze() { startWork(snoozeSeconds, reason: "snoozed") }
    func longSnooze() {
        transition(to: .snoozed(until: Date().addingTimeInterval(longSnoozeSeconds)),
                   reason: "long snooze by user (\(Int(longSnoozeSeconds))s)")
    }

    // MARK: - Internals

    private func startWork(_ seconds: TimeInterval, reason: String) {
        transition(to: .working(deadline: Date().addingTimeInterval(seconds)), reason: "\(reason) (\(Int(seconds))s)")
    }

    private func transition(to newState: State, reason: String) {
        guard newState != state else { return }
        log("\(Self.name(of: state)) -> \(Self.name(of: newState)): \(reason)")
        state = newState
        onStateChange?(newState)
    }

    @objc private func tick() {
        let before = state
        switch state {
        case .working(let deadline):
            let idle = Self.secondsSinceLastInput()
            if idle >= idleSeconds {
                transition(to: .idle, reason: "no input for \(Int(idle))s, counting as a break")
            } else if deadline <= Date() {
                transition(to: .overlay(since: Date()), reason: "work period finished")
            }
        case .idle:
            if Self.secondsSinceLastInput() < idleSeconds {
                startWork(workSeconds, reason: "input resumed after idle")
            }
        case .snoozed(let until):
            if until <= Date() {
                startWork(workSeconds, reason: "long snooze finished")
            }
        case .paused, .overlay, .asleep:
            break
        }
        if state == before { onTick?() }   // a transition already triggered onStateChange
    }

    @objc private func away(_ note: Notification) {
        if case .working = state {
            transition(to: .idle, reason: note.name.rawValue)
        }
    }

    @objc private func willSleep() {
        switch state {
        case .paused, .snoozed: break         // keep a manual pause or long snooze as is
        default: transition(to: .asleep, reason: "system going to sleep")
        }
    }

    @objc private func back(_ note: Notification) {
        switch state {
        case .paused, .snoozed: return        // respect a manual pause or long snooze
        case .working where Date().timeIntervalSince(lastWakeReset) < 2:
            return                            // wake and screen wake (or unlock and session active) arrive together
        default: break
        }
        startWork(workSeconds, reason: note.name.rawValue)
        lastWakeReset = Date()
    }

    /// kCGAnyInputEventType from the HID system state; readable without any TCC permission.
    private static func secondsSinceLastInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
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
