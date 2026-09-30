import AppKit
import ServiceManagement
import SwiftUI

/// A user-adjustable duration, stored in UserDefaults as whole minutes.
enum Setting: String, CaseIterable, Identifiable {
    case work = "workMinutes"
    case snooze = "snoozeMinutes"
    case idle = "idleMinutes"
    case longSnooze = "longSnoozeMinutes"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .work: return "Work period"
        case .snooze: return "Break snooze"
        case .idle: return "Idle counts as break after"
        case .longSnooze: return "Long snooze"
        }
    }

    var defaultMinutes: Int {
        switch self {
        case .work: return 20
        case .snooze: return 5
        case .idle: return 5
        case .longSnooze: return 60
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .work: return 1...180
        case .snooze, .idle: return 1...60
        case .longSnooze: return 5...480
        }
    }

    var step: Int { self == .longSnooze ? 5 : 1 }

    private var envKey: String {
        switch self {
        case .work: return "FOCUS_WORK_SECONDS"
        case .snooze: return "FOCUS_SNOOZE_SECONDS"
        case .idle: return "FOCUS_IDLE_SECONDS"
        case .longSnooze: return "FOCUS_LONG_SNOOZE_SECONDS"
        }
    }

    /// The FOCUS_* env var in seconds, a testing hook that overrides the stored value.
    var envOverride: TimeInterval? {
        ProcessInfo.processInfo.environment[envKey].flatMap(TimeInterval.init).flatMap { $0 > 0 ? $0 : nil }
    }

    func clamp(_ minutes: Int) -> Int { min(max(minutes, range.lowerBound), range.upperBound) }

    var seconds: TimeInterval {
        envOverride ?? TimeInterval(clamp(UserDefaults.standard.object(forKey: rawValue) as? Int ?? defaultMinutes) * 60)
    }
}

/// How many characters of the current focus the menu bar shows.
enum FocusDisplay {
    static let key = "focusDisplayLength"
    static let title = "Characters shown in menu bar"
    static let defaultLength = 10
    static let range = 1...40

    static func clamp(_ length: Int) -> Int { min(max(length, range.lowerBound), range.upperBound) }

    static var length: Int { clamp(UserDefaults.standard.object(forKey: key) as? Int ?? defaultLength) }

    static func displayed(_ focus: String) -> String {
        var prefix = focus.split(whereSeparator: \.isNewline).joined(separator: " ").prefix(length)
        while prefix.last?.isWhitespace == true { prefix.removeLast() }
        return String(prefix)
    }
}

/// Launch at login via SMAppService. The system is the source of truth; nothing is cached here.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var error: String?

    var isOn: Bool { status == .enabled || status == .requiresApproval }

    func refresh() { status = SMAppService.mainApp.status }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
        log("launch at login \(on ? "on" : "off"): status=\(status.rawValue)")
    }
}

private struct NumberRow: View {
    let title: String
    let range: ClosedRange<Int>
    var step = 1
    var unit: String?
    var disabled = false
    @AppStorage private var value: Int
    @FocusState private var focused: Bool

    init(_ title: String, key: String, default defaultValue: Int, range: ClosedRange<Int>,
         step: Int = 1, unit: String? = nil, disabled: Bool = false) {
        (self.title, self.range, self.step, self.unit, self.disabled) = (title, range, step, unit, disabled)
        _value = AppStorage(wrappedValue: defaultValue, key)
    }

    init(_ setting: Setting) {
        self.init(setting.title, key: setting.rawValue, default: setting.defaultMinutes, range: setting.range,
                  step: setting.step, unit: "min", disabled: setting.envOverride != nil)
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: $value, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                    .focused($focused)
                    .onSubmit(commit)
                Stepper(title, value: $value, in: range, step: step)
                    .labelsHidden()
                if let unit { Text(unit) }
            }
        }
        .disabled(disabled)
        // Clamp on commit, not per keystroke, so e.g. "30" can be typed into a 5...480 field.
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func commit() { value = min(max(value, range.lowerBound), range.upperBound) }
}

private struct ExtensionRow: View {
    let ext: any OverlayExtension
    @AppStorage private var isOn: Bool

    init(_ ext: any OverlayExtension) {
        self.ext = ext
        _isOn = AppStorage(wrappedValue: false, ext.enabledKey)
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(ext.title)
            Text(ext.summary)
        }
    }
}

private struct GeneralPane: View {
    @ObservedObject var loginItem: LoginItem

    var body: some View {
        Form {
            Section {
                ForEach(Setting.allCases) { NumberRow($0) }
            } footer: {
                Text("Work and snooze changes apply from the next period.").foregroundStyle(.secondary)
            }
            Section {
                NumberRow(FocusDisplay.title, key: FocusDisplay.key, default: FocusDisplay.defaultLength,
                          range: FocusDisplay.range)
            }
            Section {
                Toggle("Launch at login", isOn: Binding(get: { loginItem.isOn }, set: { loginItem.set($0) }))
                if loginItem.status == .requiresApproval {
                    Text("Allow Never Press Start in System Settings > General > Login Items.")
                        .foregroundStyle(.secondary)
                    Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let error = loginItem.error {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .settingsPane()
    }
}

private struct ExtensionsPane: View {
    var body: some View {
        Form {
            ForEach(OverlayExtensions.all, id: \.id) { ExtensionRow($0) }
        }
        .settingsPane()
    }
}

private extension View {
    func settingsPane() -> some View {
        formStyle(.grouped).frame(width: 420).fixedSize(horizontal: false, vertical: true)
    }
}

/// Toolbar pane switcher (HIG Settings) that remembers the last viewed pane.
private final class SettingsTabViewController: NSTabViewController {
    private static let paneKey = "settingsPane"

    init(panes: [(title: String, symbol: String, view: AnyView)]) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        let saved = UserDefaults.standard.integer(forKey: Self.paneKey)
        for pane in panes {
            let host = NSHostingController(rootView: pane.view)
            host.sizingOptions = .preferredContentSize
            host.title = pane.title
            let item = NSTabViewItem(viewController: host)
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            addTabViewItem(item)
        }
        selectedTabViewItemIndex = panes.indices.contains(saved) ? saved : 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        UserDefaults.standard.set(selectedTabViewItemIndex, forKey: Self.paneKey)
    }
}

/// One reusable Settings window hosting the SwiftUI panes.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let loginItem = LoginItem()

    init() {
        let window = NSWindow(contentViewController: SettingsTabViewController(panes: [
            ("General", "gearshape", AnyView(GeneralPane(loginItem: loginItem))),
            ("Extensions", "puzzlepiece.extension", AnyView(ExtensionsPane())),
        ]))
        window.toolbarStyle = .preference
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        NotificationCenter.default.addObserver(
            self, selector: #selector(becameKey), name: NSWindow.didBecomeKeyNotification, object: window)
        NotificationCenter.default.addObserver(
            self, selector: #selector(willClose), name: NSWindow.willCloseNotification, object: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func becameKey() { loginItem.refresh() }

    /// Ends editing so a typed value is committed (and clamped) when the window closes.
    @objc private func willClose() { window?.makeFirstResponder(nil) }
}
