import AppKit
import Carbon

/// Full-screen break overlay. A non-activating panel at screen-saver level on every
/// Space and display, above full-screen apps, without activating the app.
/// Never uses native full screen / kiosk mode.
final class OverlayWindow: NSPanel {
    private let elapsedLabel = NSTextField(labelWithString: "0:00")

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(screen: NSScreen, extensionViews: [NSView], onBackToWork: @escaping () -> Void, onSnooze: @escaping () -> Void,
         snoozeMinutes: Int) {
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
        buttons.spacing = 24
        snooze.widthAnchor.constraint(equalTo: back.widthAnchor).isActive = true
        snooze.setAccessibilityLabel("Snooze for \(snoozeMinutes) minutes")

        let stack = NSStackView(views: [title] + extensionViews + [elapsedLabel, buttons])
        stack.orientation = .vertical
        stack.spacing = 24
        stack.setCustomSpacing(64, after: elapsedLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        contentView = content
        initialFirstResponder = snooze   // Full Keyboard Access starts on Snooze, not an extension's control
    }

    func update(elapsed: TimeInterval) {
        let s = Int(elapsed)
        elapsedLabel.stringValue = String(format: "Break so far %d:%02d", s / 60, s % 60)
    }
}

/// Button that runs a closure and accepts the first click even though the app is inactive.
class ClosureButton: NSButton {
    private let handler: () -> Void

    init(action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        target = self
        action = #selector(fire)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func fire() { handler() }
}

/// One entry in an overlay context menu.
struct OverlayMenuItem {
    let title: String
    var isEnabled = true
    let action: () -> Void
}

/// ClosureButton with a context menu on right-click or ctrl-click, built fresh from `items` each time it opens.
final class MenuButton: ClosureButton {
    private let items: () -> [OverlayMenuItem]

    init(action handler: @escaping () -> Void, items: @escaping () -> [OverlayMenuItem]) {
        self.items = items
        super.init(action: handler)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items() {
            let action = MenuAction(item.action)
            let menuItem = NSMenuItem(title: item.title, action: #selector(MenuAction.fire), keyEquivalent: "")
            menuItem.isEnabled = item.isEnabled
            menuItem.target = action
            menuItem.representedObject = action   // target is weak
            menu.addItem(menuItem)
        }
        return menu.items.isEmpty ? nil : menu
    }

    /// AppKit passes a ctrl-click on to mouseDown when there's no menu; it must never count as a click.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { return }
        super.mouseDown(with: event)
    }
}

/// Target for a menu item's closure.
private final class MenuAction: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire() { handler() }
}

private final class ActionButton: ClosureButton {
    init(title: String, action handler: @escaping () -> Void) {
        super.init(action: handler)
        self.title = title
        bezelStyle = .glass
        controlSize = .extraLarge
        tintProminence = .none   // Return key equivalent would otherwise tint "Back to work" blue
        font = .systemFont(ofSize: 20, weight: .semibold)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 56),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Owns one overlay window per screen plus the Esc hot key while showing.
@MainActor
final class OverlayController: NSObject {
    private var windows: [OverlayWindow] = []
    private var since = Date()
    private let onBackToWork: () -> Void
    private let onSnooze: () -> Void
    private let snoozeSeconds: () -> TimeInterval
    private var extensions: [any OverlayExtension] = []   // enabled ones, fixed for the whole break
    private lazy var escape = HotKey(keyCode: kVK_Escape) { [weak self] in self?.onBackToWork() }
    private lazy var undo = HotKey(keyCode: kVK_ANSI_Z, modifiers: cmdKey) { [weak self] in
        self?.extensions.forEach { $0.undo() }
    }

    init(snoozeSeconds: @escaping () -> TimeInterval, onBackToWork: @escaping () -> Void, onSnooze: @escaping () -> Void) {
        self.snoozeSeconds = snoozeSeconds
        self.onBackToWork = onBackToWork
        self.onSnooze = onSnooze
    }

    private var raiseObserversActive = false
    private static let raiseTriggers = [
        NSWorkspace.activeSpaceDidChangeNotification,     // e.g. switching into a full-screen Space
        NSWorkspace.didActivateApplicationNotification,   // another app coming forward
    ]
    /// A context menu is open: Esc must close it, not end the break.
    private static let menuTracking: [(Notification.Name, Selector)] = [
        (NSMenu.didBeginTrackingNotification, #selector(menuDidBeginTracking)),
        (NSMenu.didEndTrackingNotification, #selector(menuDidEndTracking)),
    ]

    var isShowing: Bool { !windows.isEmpty }

    func show(since: Date) {
        if !isShowing {   // not on display-change rebuilds
            extensions = OverlayExtensions.all.filter(\.isEnabled)
            extensions.forEach { $0.overlayWillShow() }
        }
        self.since = since
        windows.forEach { $0.orderOut(nil) }
        let snoozeMinutes = max(1, Int((snoozeSeconds() / 60).rounded()))
        windows = NSScreen.screens.map {
            OverlayWindow(screen: $0, extensionViews: extensions.map { $0.makeOverlayView() },
                          onBackToWork: onBackToWork, onSnooze: onSnooze, snoozeMinutes: snoozeMinutes)
        }
        escape.register()   // global Esc and ⌘Z grabs only while the overlay is up
        undo.register()
        if !raiseObserversActive {
            // Re-raise immediately instead of waiting for the 1 s timer.
            for name in Self.raiseTriggers {
                NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(raise), name: name, object: nil)
            }
            for (name, selector) in Self.menuTracking {
                NotificationCenter.default.addObserver(self, selector: selector, name: name, object: nil)
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
        undo.unregister()
        for name in Self.raiseTriggers {
            NSWorkspace.shared.notificationCenter.removeObserver(self, name: name, object: nil)
        }
        for (name, _) in Self.menuTracking {
            NotificationCenter.default.removeObserver(self, name: name, object: nil)
        }
        raiseObserversActive = false
        extensions.forEach { $0.overlayDidHide() }
        extensions = []
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

    @objc private func menuDidBeginTracking() { escape.unregister() }
    @objc private func menuDidEndTracking() { escape.register() }

    @objc private func raise() {
        windows.forEach { $0.orderFrontRegardless() }
        windows.first?.makeKey()   // best effort, so Return still works after Cmd-Tab
    }
}
