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

    /// Default on: register once, on the first launch from an Applications folder (not build/),
    /// and never again, so turning it off sticks.
    static func setUpOnFirstLaunch() {
        let key = "didInitialLoginItemSetup"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL
        let appDirs = FileManager.default.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])
        guard appDirs.map(\.standardizedFileURL).contains(parent) else {
            return log("not in an Applications folder; skipping login item setup")
        }
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: key)
            log("registered login item on first launch")
        } catch {
            log("login item registration failed: \(error.localizedDescription)")
        }
    }
}

private struct MinutesRow: View {
    let setting: Setting
    @AppStorage private var minutes: Int
    @FocusState private var focused: Bool

    init(_ setting: Setting) {
        self.setting = setting
        _minutes = AppStorage(wrappedValue: setting.defaultMinutes, setting.rawValue)
    }

    var body: some View {
        LabeledContent(setting.title) {
            HStack(spacing: 4) {
                TextField(setting.title, value: $minutes, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                    .focused($focused)
                    .onSubmit(commit)
                Stepper(setting.title, value: $minutes, in: setting.range, step: setting.step)
                    .labelsHidden()
                Text("min")
            }
        }
        .disabled(setting.envOverride != nil)
        // Clamp on commit, not per keystroke, so e.g. "30" can be typed into a 5...480 field.
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func commit() { minutes = setting.clamp(minutes) }
}

private struct SettingsView: View {
    @ObservedObject var loginItem: LoginItem

    var body: some View {
        Form {
            Section {
                ForEach(Setting.allCases) { MinutesRow($0) }
            } footer: {
                Text("Work and snooze changes apply from the next period.").foregroundStyle(.secondary)
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
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One reusable Settings window hosting the SwiftUI form.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let loginItem = LoginItem()

    init() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(loginItem: loginItem)))
        window.title = "Never Press Start Settings"
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
