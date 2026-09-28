import AppKit
import Carbon

/// Full-screen break overlay. A non-activating panel at screen-saver level on every
/// Space and display, above full-screen apps, without activating the app.
/// Never uses native full screen / kiosk mode.
final class OverlayWindow: NSPanel {
    private let elapsedLabel = NSTextField(labelWithString: "0:00")

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(screen: NSScreen, onBackToWork: @escaping () -> Void, onSnooze: @escaping () -> Void, snoozeMinutes: Int) {
        // Created hidden; everything is configured here before the first orderFrontRegardless().
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .canJoinAllApplications]
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.85)
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)

        let title = NSTextField(labelWithString: "Take a break")
        title.font = .systemFont(ofSize: 72, weight: .bold)
        title.textColor = .white
        title.isSelectable = false   // no force-click Look Up escape
        title.isEditable = false

        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 32, weight: .regular)
        elapsedLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        elapsedLabel.isSelectable = false
        elapsedLabel.isEditable = false

        let back = ActionButton(title: "Back to work", action: onBackToWork)
        back.keyEquivalent = "\r"
        let snooze = ActionButton(title: "Snooze \(snoozeMinutes) min", action: onSnooze)
        let buttons = NSStackView(views: [snooze, back])
        buttons.spacing = 16

        let stack = NSStackView(views: [title, elapsedLabel, buttons])
        stack.orientation = .vertical
        stack.spacing = 24
        stack.setCustomSpacing(48, after: elapsedLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        contentView = content
    }

    func update(elapsed: TimeInterval) {
        let s = Int(elapsed)
        elapsedLabel.stringValue = String(format: "Break so far %d:%02d", s / 60, s % 60)
    }
}

/// Button that runs a closure and accepts the first click even though the app is inactive.
private final class ActionButton: NSButton {
    private let handler: () -> Void

    init(title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        controlSize = .large
        font = .systemFont(ofSize: 18)
        target = self
        action = #selector(fire)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func fire() { handler() }
}

/// Owns one overlay window per screen plus the Esc hot key while showing.
@MainActor
final class OverlayController: NSObject {
    private var windows: [OverlayWindow] = []
    private var since = Date()
    private let onBackToWork: () -> Void
    private let onSnooze: () -> Void
    private let snoozeMinutes: Int
    private lazy var escape = HotKey(keyCode: kVK_Escape) { [weak self] in self?.onBackToWork() }

    init(snoozeSeconds: TimeInterval, onBackToWork: @escaping () -> Void, onSnooze: @escaping () -> Void) {
        self.snoozeMinutes = max(1, Int((snoozeSeconds / 60).rounded()))
        self.onBackToWork = onBackToWork
        self.onSnooze = onSnooze
    }

    private var raiseObserversActive = false
    private static let raiseTriggers = [
        NSWorkspace.activeSpaceDidChangeNotification,     // e.g. switching into a full-screen Space
        NSWorkspace.didActivateApplicationNotification,   // another app coming forward
    ]

    var isShowing: Bool { !windows.isEmpty }

    func show(since: Date) {
        self.since = since
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map {
            OverlayWindow(screen: $0, onBackToWork: onBackToWork, onSnooze: onSnooze, snoozeMinutes: snoozeMinutes)
        }
        escape.register()   // global Esc grab only while the overlay is up
        if !raiseObserversActive {
            // Re-raise immediately instead of waiting for the 1 s timer.
            for name in Self.raiseTriggers {
                NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(raise), name: name, object: nil)
            }
            raiseObserversActive = true
        }
        refresh()                   // orderFrontRegardless() on every window
        windows.first?.makeKey()    // best effort; the app is never activated
        log("overlay shown on \(windows.count) screen(s)")
    }

    func hide() {
        guard isShowing else { return }
        escape.unregister()
        for name in Self.raiseTriggers {
            NSWorkspace.shared.notificationCenter.removeObserver(self, name: name, object: nil)
        }
        raiseObserversActive = false
        windows.forEach { $0.orderOut(nil) }
        windows = []
        log("overlay hidden")
    }

    /// Called every second: update the counter and re-assert front-most order.
    func refresh() {
        let elapsed = Date().timeIntervalSince(since)
        for window in windows {
            window.update(elapsed: elapsed)
            window.orderFrontRegardless()
        }
    }

    @objc private func raise() {
        windows.forEach { $0.orderFrontRegardless() }
        windows.first?.makeKey()   // best effort, so Return still works after Cmd-Tab
    }
}
