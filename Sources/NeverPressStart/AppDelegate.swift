import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = PomodoroEngine()
    private lazy var overlay = OverlayController(
        snoozeSeconds: engine.snoozeSeconds,
        onBackToWork: { [weak self] in self?.engine.backToWork() },
        onSnooze: { [weak self] in self?.engine.snooze() }
    )
    private var statusItem: NSStatusItem!
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        statusItem.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.addItem(pauseItem)
        menu.addItem(NSMenuItem(title: "Reset timer", action: #selector(reset), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Take break now", action: #selector(breakNow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Snooze \(Self.duration(engine.longSnoozeSeconds))", action: #selector(longSnooze), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Never Press Start", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.filter { $0.action != #selector(NSApplication.terminate(_:)) }.forEach { $0.target = self }
        menu.autoenablesItems = false   // otherwise pauseItem.isEnabled is ignored
        statusItem.menu = menu

        engine.onStateChange = { [weak self] state in self?.stateChanged(state) }
        engine.onTick = { [weak self] in self?.updateStatus() }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        engine.start()
    }

    private func stateChanged(_ state: PomodoroEngine.State) {
        if case .overlay(let since) = state {
            overlay.show(since: since)
        } else {
            overlay.hide()
        }
        pauseItem.title = { switch state { case .paused, .snoozed: return "Resume"; default: return "Pause" } }()
        pauseItem.isEnabled = { switch state { case .working, .paused, .snoozed: return true; default: return false } }()
        updateStatus()
    }

    private func updateStatus() {
        switch engine.state {
        case .working(let deadline):
            setStatus(symbol: nil, text: Self.mmss(deadline.timeIntervalSinceNow))
        case .paused(let remaining):
            setStatus(symbol: "pause.fill", text: Self.mmss(remaining))
        case .idle, .asleep:
            setStatus(symbol: "moon.zzz", text: "")
        case .snoozed(let until):
            setStatus(symbol: "zzz", text: Self.mmss(until.timeIntervalSinceNow))
        case .overlay:
            setStatus(symbol: "cup.and.saucer.fill", text: "")
            overlay.refresh()
        }
    }

    private func setStatus(symbol: String?, text: String) {
        guard let button = statusItem.button else { return }
        button.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        button.title = text
    }

    /// "1 hour", "2 hours", "20 min", "20 s".
    private static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s % 3600 == 0 { return s == 3600 ? "1 hour" : "\(s / 3600) hours" }
        if s % 60 == 0 { return "\(s / 60) min" }
        return "\(s) s"
    }

    private static func mmss(_ interval: TimeInterval) -> String {
        let s = max(0, Int(interval.rounded(.up)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    @objc private func togglePause() { engine.togglePause() }
    @objc private func reset() { engine.reset() }
    @objc private func breakNow() { engine.breakNow() }
    @objc private func longSnooze() { engine.longSnooze() }

    @objc private func screensChanged() {
        // Rebuild so each display (including newly attached ones) gets a window.
        if case .overlay(let since) = engine.state { overlay.show(since: since) }
    }
}
