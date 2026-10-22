import AppKit
import EventKit
import SwiftUI

/// The next Apple Calendar event, shown in the menu bar so you can take your break before it.
/// The app's only permission: full calendar access, asked when this extension is turned on.
final class CalendarEvents: OverlayExtension {
    struct Event {
        let title: String
        let start: Date
        var isAllDay = false
        var declined = false
    }

    static let window: TimeInterval = 20 * 60
    static let refetchInterval: TimeInterval = 60

    let storage = ExtensionStorage(id: "calendar")
    let title = "Calendar"
    let summary = "Shows your next calendar event in the menu bar and offers a break before it."
    let toggleTitle = "Show upcoming events"

    private lazy var store = EKEventStore()
    private var events: [Event] = []
    private var fetchedAt: Date?
    private var hadAccess = false

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fetchedAt = nil }
        }
    }

    static var status: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    static var hasAccess: Bool { status == .fullAccess }

    var settingsView: AnyView? { AnyView(CalendarAccessView(enabledKey: enabledKey, request: requestAccess)) }

    /// Asks for full access; true if granted.
    func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        log("calendar access \(granted ? "granted" : "denied")")
        fetchedAt = nil
        return granted
    }

    /// The next event within `window`, from a cache refetched at most once a minute or when the store changes.
    func upcoming(now: Date = Date()) -> Event? {
        guard isEnabled, Self.hasAccess else { return nil }
        if !hadAccess {
            store.reset()   // a store made before the grant returns no events until reset
            (hadAccess, fetchedAt) = (true, nil)
        }
        if fetchedAt.map({ now.timeIntervalSince($0) >= Self.refetchInterval }) ?? true {
            fetchedAt = now
            // Fetch a minute past the window so the cache covers it until the next refetch.
            let predicate = store.predicateForEvents(withStart: now, end: now + Self.window + Self.refetchInterval,
                                                     calendars: nil)
            events = store.events(matching: predicate).filter { $0.status != .canceled }.map {
                Event(title: $0.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Event", start: $0.startDate, isAllDay: $0.isAllDay,
                      declined: $0.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined)
            }
        }
        return Self.upcoming(in: events, now: now)
    }

    /// The earliest timed, not-declined event starting after `now` and within `window`.
    static func upcoming(in events: [Event], now: Date) -> Event? {
        events.filter { !$0.isAllDay && !$0.declined && $0.start > now && $0.start <= now + window }
            .min { $0.start < $1.start }
    }

    /// "Standup in 12m", minutes rounded up, title cut like the focus text.
    static func menuBarText(_ event: Event, now: Date) -> String {
        "\(FocusDisplay.displayed(event.title)) in \(Int((event.start.timeIntervalSince(now) / 60).rounded(.up)))m"
    }

    func makeOverlayView() -> NSView {
        let view = JokeView()
        let next = upcoming()
        view.label.stringValue = next.map { "Next: \($0.title) at \($0.start.formatted(date: .omitted, time: .shortened))" } ?? ""
        view.isHidden = next == nil
        return view
    }
}

/// Requests access when the toggle turns on; if denied, links to Privacy & Security > Calendars.
private struct CalendarAccessView: View {
    static let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    let request: () async -> Bool
    @AppStorage private var isOn: Bool
    @State private var status = CalendarEvents.status

    init(enabledKey: String, request: @escaping () async -> Bool) {
        self.request = request
        _isOn = AppStorage(wrappedValue: false, enabledKey)
    }

    var body: some View {
        Group {
            if !isOn || [.notDetermined, .fullAccess].contains(status) {
                Text("Reads events from Apple Calendar.").foregroundStyle(.secondary)
            } else {
                Text("Calendar access is off. Allow Never Press Start in System Settings > Privacy & Security > Calendars.")
                    .foregroundStyle(.secondary)
                Button("Open Calendars Settings") { NSWorkspace.shared.open(Self.privacyURL) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = CalendarEvents.status
        }
        .task(id: isOn) {
            if isOn && !CalendarEvents.hasAccess { _ = await request() }
            status = CalendarEvents.status
        }
    }
}
