import AppKit
import EventKit
import SwiftUI

/// Apple Calendar events: a break `lead` before each one, the timer snoozed while it runs, and the next one in the
/// menu bar. The app's only permission: full calendar access, asked when this extension is turned on.
final class CalendarEvents: OverlayExtension, MeetingSchedule {
    struct Event {
        let id: String
        let title: String
        let start: Date
        let end: Date
        var isAllDay = false
        var declined = false
        var isFree = false

        var isRelevant: Bool { !isAllDay && !declined && !isFree }
    }

    /// FOCUS_CALENDAR_LEAD_SECONDS, else 20 minutes.
    static var lead: TimeInterval {
        ProcessInfo.processInfo.environment["FOCUS_CALENDAR_LEAD_SECONDS"].flatMap(TimeInterval.init)
            .flatMap { $0 > 0 ? $0 : nil } ?? 20 * 60
    }
    static let refetchInterval: TimeInterval = 60
    /// Less notice than this and the break is skipped: there's no time for one.
    static let minimumNotice: TimeInterval = 60

    let storage: ExtensionStorage
    let title = "Calendar"
    let summary = "Brings up a break 20 minutes before each event and pauses the timer while it runs. "
        + "Shows the next event in the menu bar."
    let toggleTitle = "Use Apple Calendar"

    private lazy var store = EKEventStore()
    private var events: [Event] = []
    private var fetchedAt: Date?
    private var hadAccess = false
    private let views = NSHashTable<JokeView>.weakObjects()
    private var timer: Timer?

    init(defaults: UserDefaults = .standard) {
        storage = ExtensionStorage(id: "calendar", defaults: defaults)
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fetchedAt = nil }
        }
    }

    static var status: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    static var hasAccess: Bool { status == .fullAccess }

    var breakBefore: Bool { storage.defaults.object(forKey: storage.key("breakBefore")) as? Bool ?? true }

    var settingsView: AnyView? {
        AnyView(CalendarAccessView(enabledKey: enabledKey, breakBeforeKey: storage.key("breakBefore"), request: requestAccess))
    }

    /// Asks for full access; true if granted.
    func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        log("calendar access \(granted ? "granted" : "denied")")
        fetchedAt = nil
        return granted
    }

    /// Events from 12 hours ago to just past `lead`, from a cache refetched at most once a minute or when the store
    /// changes; nil unless enabled with access.
    private func cachedEvents(now: Date) -> [Event]? {
        guard isEnabled, Self.hasAccess else { return nil }
        if !hadAccess {
            store.reset()   // a store made before the grant returns no events until reset
            (hadAccess, fetchedAt) = (true, nil)
        }
        if fetchedAt.map({ now.timeIntervalSince($0) >= Self.refetchInterval }) ?? true {
            fetchedAt = now
            // A minute past the lead so the cache covers it until the next refetch.
            let predicate = store.predicateForEvents(withStart: now - 12 * 3600, end: now + Self.lead + Self.refetchInterval,
                                                     calendars: nil)
            events = store.events(matching: predicate).filter { $0.status != .canceled }.map {
                Event(id: "\($0.eventIdentifier ?? $0.calendarItemIdentifier)|\($0.startDate.timeIntervalSince1970)",
                      title: $0.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Event", start: $0.startDate, end: $0.endDate,
                      isAllDay: $0.isAllDay,
                      declined: $0.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined,
                      isFree: $0.availability == .free)
            }
        }
        return events
    }

    /// The next event within `lead`.
    func upcoming(now: Date = Date()) -> Event? { cachedEvents(now: now).flatMap { Self.upcoming(in: $0, now: now) } }

    // MARK: - MeetingSchedule

    func claimBreak(now: Date) -> Bool {
        guard breakBefore, let events = cachedEvents(now: now) else { return false }
        let (due, keys) = Self.breakDue(in: events, handled: handled, now: now)
        markHandled(keys, now: now)
        return due
    }

    func claimMeeting(now: Date) -> Date? {
        guard breakBefore, let events = cachedEvents(now: now) else { return nil }
        let handled = handled
        let keys = Self.inProgress(in: events, now: now).filter { !handled.contains("m|" + $0.id) }
        markHandled(keys.map { "m|" + $0.id }, now: now)
        return keys.map(\.end).max()
    }

    /// "b|<id>" and "m|<id>" for breaks and meetings already taken care of, kept across relaunches.
    var handled: Set<String> { Set(storage.defaults.stringArray(forKey: storage.key("handled")) ?? []) }

    /// Adds `keys`, dropping those for events that started more than a day ago.
    func markHandled(_ keys: [String], now: Date) {
        guard !keys.isEmpty else { return }
        let kept = handled.union(keys).filter {
            $0.split(separator: "|").last.flatMap { TimeInterval($0) }.map { now.timeIntervalSince1970 - $0 < 86_400 } ?? false
        }
        storage.set(kept.sorted(), "handled")
    }

    // MARK: - Pure helpers

    /// Relevant events starting after `now` and within `lead`, earliest first.
    static func soon(in events: [Event], now: Date) -> [Event] {
        events.filter { $0.isRelevant && $0.start > now && $0.start <= now + lead }.sorted { $0.start < $1.start }
    }

    /// The earliest timed, accepted, busy event starting after `now` and within `lead`.
    static func upcoming(in events: [Event], now: Date) -> Event? { soon(in: events, now: now).first }

    /// A break is due when events have entered the lead window and none of them had one yet, unless the earliest is
    /// under a minute away. `keys` marks every event in the window, so a second one entering it doesn't fire again.
    static func breakDue(in events: [Event], handled: Set<String>, now: Date) -> (due: Bool, keys: [String]) {
        let soon = soon(in: events, now: now)
        let keys = soon.map { "b|" + $0.id }
        let fresh = keys.filter { !handled.contains($0) }
        let due = !soon.isEmpty && fresh.count == keys.count && soon[0].start.timeIntervalSince(now) >= minimumNotice
        return (due, fresh)
    }

    /// Relevant events running at `now`.
    static func inProgress(in events: [Event], now: Date) -> [Event] {
        events.filter { $0.isRelevant && $0.start <= now && now < $0.end }
    }

    /// "Standup in 12m", minutes rounded up, title cut like the focus text.
    static func menuBarText(_ event: Event, now: Date) -> String {
        "\(FocusDisplay.displayed(event.title)) in \(minutes(until: event, now: now))m"
    }

    /// "Standup in 12 minutes", minutes rounded up.
    static func overlayText(_ event: Event, now: Date) -> String {
        let minutes = minutes(until: event, now: now)
        return "\(event.title) in \(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    private static func minutes(until event: Event, now: Date) -> Int {
        Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
    }

    // MARK: - Overlay

    func makeOverlayView() -> NSView {
        let view = JokeView()
        views.add(view)
        apply(to: view)
        return view
    }

    /// Counts the minutes down while the break is up.
    func overlayWillShow() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self.map { $0.views.allObjects.forEach($0.apply) } }
        }
    }

    func overlayDidHide() {
        timer?.invalidate()
        timer = nil
    }

    private func apply(to view: JokeView) {
        let now = Date()
        let text = upcoming(now: now).map { Self.overlayText($0, now: now) }
        view.label.stringValue = text ?? ""
        view.isHidden = text == nil
    }
}

/// Requests access when the toggle turns on; if denied, links to Privacy & Security > Calendars.
private struct CalendarAccessView: View {
    static let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    let request: () async -> Bool
    @AppStorage private var isOn: Bool
    @AppStorage private var breakBefore: Bool
    @State private var status = CalendarEvents.status

    init(enabledKey: String, breakBeforeKey: String, request: @escaping () async -> Bool) {
        self.request = request
        _isOn = AppStorage(wrappedValue: false, enabledKey)
        _breakBefore = AppStorage(wrappedValue: true, breakBeforeKey)
    }

    var body: some View {
        Group {
            Toggle("Take a break 20 minutes before events", isOn: $breakBefore)
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
