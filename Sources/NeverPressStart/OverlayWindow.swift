import AppKit
import Carbon

/// Full-screen break overlay. A non-activating panel at screen-saver level on every
/// Space and display, above full-screen apps, without activating the app.
/// Never uses native full screen / kiosk mode.
final class OverlayWindow: NSPanel {
    private let elapsedLabel = NSTextField(labelWithString: "0:00")
    private let extensionLabel = NSTextField(wrappingLabelWithString: "")

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

        extensionLabel.font = .systemFont(ofSize: 26, weight: .regular)
        extensionLabel.textColor = NSColor.white.withAlphaComponent(0.9)
        extensionLabel.alignment = .center
        extensionLabel.preferredMaxLayoutWidth = 800
        extensionLabel.maximumNumberOfLines = 4   // a long gist can't push the buttons off screen
        extensionLabel.lineBreakMode = .byTruncatingTail
        extensionLabel.isSelectable = false
        extensionLabel.isEditable = false
        extensionLabel.isHidden = true   // hidden views are detached from the stack, so layout is unchanged

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

        let stack = NSStackView(views: [title, extensionLabel, elapsedLabel, buttons])
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
    }

    func setExtensionText(_ text: String?) {
        extensionLabel.stringValue = text ?? ""
        extensionLabel.isHidden = text == nil
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
        bezelStyle = .glass
        controlSize = .extraLarge
        tintProminence = .none   // Return key equivalent would otherwise tint "Back to work" blue
        font = .systemFont(ofSize: 20, weight: .semibold)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 56),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
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
    private let snoozeSeconds: () -> TimeInterval
    private var extensionTexts: [String: String] = [:]   // by extension id
    private var extensionFetches: [Task<Void, Never>] = []
    private lazy var escape = HotKey(keyCode: kVK_Escape) { [weak self] in self?.onBackToWork() }

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

    var isShowing: Bool { !windows.isEmpty }

    func show(since: Date) {
        if !isShowing { loadExtensions() }   // not on display-change rebuilds
        self.since = since
        windows.forEach { $0.orderOut(nil) }
        let snoozeMinutes = max(1, Int((snoozeSeconds() / 60).rounded()))
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
        applyExtensionText()
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
        extensionFetches.forEach { $0.cancel() }
        extensionFetches = []
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

    /// Shows cached text from each enabled extension now, then fresh text as fetches return.
    private func loadExtensions() {
        let enabled = OverlayExtensions.all.filter(\.isEnabled)
        extensionTexts = Dictionary(uniqueKeysWithValues: enabled.compactMap { ext in ext.cachedText.map { (ext.id, $0) } })
        extensionFetches = enabled.map { ext in
            Task { [weak self] in
                guard let text = await ext.fetch(), let self, self.isShowing else { return }
                self.extensionTexts[ext.id] = text
                self.applyExtensionText()
            }
        }
    }

    private func applyExtensionText() {
        let texts = OverlayExtensions.all.compactMap { extensionTexts[$0.id] }
        let text = texts.isEmpty ? nil : texts.joined(separator: "\n\n")
        windows.forEach { $0.setExtensionText(text) }
    }

    @objc private func raise() {
        windows.forEach { $0.orderFrontRegardless() }
        windows.first?.makeKey()   // best effort, so Return still works after Cmd-Tab
    }
}
