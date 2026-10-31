import AppKit
import Foundation
import Testing
@testable import NeverPressStart

@MainActor
@Suite(.serialized)
struct ExtensionsTests {
    private let joke = OverlayExtensions.all.first { $0 is HourlyJoke }!

    @Test func extensionsAreDisabledByDefault() {
        #expect(joke.enabledKey == "extension.hourlyJoke.enabled")
        #expect(DrinkWater().enabledKey == "extension.drinkWater.enabled")
        for ext in OverlayExtensions.all {
            UserDefaults.standard.removeObject(forKey: ext.enabledKey)
            #expect(!ext.isEnabled)
            UserDefaults.standard.set(true, forKey: ext.enabledKey)
            #expect(ext.isEnabled)
            UserDefaults.standard.removeObject(forKey: ext.enabledKey)
        }
    }

    @Test func storageIsNamespaced() {
        #expect(joke.storage.key("cached") == "extension.hourlyJoke.cached")
    }

    @Test func registryHasUniqueIDs() {
        let ids = OverlayExtensions.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids == ["hourlyJoke", "messages", "focusPicker", "drinkWater", "breakChime", "calendar"])
    }

    @Test func jokeIsTrimmed() {
        #expect(HourlyJoke.joke(from: Data("  What am I?\n\n".utf8), status: 200) == "What am I?")
    }

    @Test func jokeViewHugsShortAndScrollsLong() {
        let view = JokeView()
        let stack = NSStackView(views: [view])   // as in the overlay
        stack.orientation = .vertical
        view.label.stringValue = "Short."
        stack.layoutSubtreeIfNeeded()
        #expect(view.frame.height == view.label.frame.height)
        view.label.stringValue = String(repeating: "A long joke line. ", count: 40)
        stack.layoutSubtreeIfNeeded()
        #expect(view.label.frame.height > view.frame.height)
    }

    @Test func emptyOrErrorResponseIsIgnored() {
        #expect(HourlyJoke.joke(from: Data(" \n".utf8), status: 200) == nil)
        #expect(HourlyJoke.joke(from: Data("Not Found".utf8), status: 404) == nil)
        #expect(HourlyJoke.joke(from: Data("joke".utf8), status: 0) == nil)
    }

    @Test func waterDayIsLocalCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        let date = Date(timeIntervalSince1970: 1_790_000_000)   // 2026-09-21 14:13 UTC, 22:13 in Hong Kong
        #expect(DrinkWater.day(for: date, calendar: calendar) == "2026-09-21")
        #expect(DrinkWater.day(for: date + 2 * 3600, calendar: calendar) == "2026-09-22")
    }

    @Test func waterCountKeepsSameDayAndResetsOnNewDay() {
        #expect(DrinkWater.count(storedDay: "2026-09-30", storedCount: 3, today: "2026-09-30") == 3)
        #expect(DrinkWater.count(storedDay: "2026-09-29", storedCount: 3, today: "2026-09-30") == 0)
        #expect(DrinkWater.count(storedDay: nil, storedCount: 0, today: "2026-09-30") == 0)
    }

    @Test func glassesPersistAndRollOver() {
        let defaults = UserDefaults(suiteName: "ExtensionsTests.water")!
        defaults.removePersistentDomain(forName: "ExtensionsTests.water")
        var now = Date(timeIntervalSince1970: 1_790_000_000)
        let water = DrinkWater(defaults: defaults, now: { now })
        water.addGlass()
        water.addGlass()
        #expect(DrinkWater(defaults: defaults, now: { now }).count == 2)
        #expect(defaults.integer(forKey: "extension.drinkWater.count") == 2)
        now += 86_400
        #expect(water.count == 0)
        water.addGlass()
        #expect(water.count == 1)
        defaults.removePersistentDomain(forName: "ExtensionsTests.water")
    }

    @Test func removeGlassFloorsAtZeroAndIgnoresStaleDay() {
        let defaults = UserDefaults(suiteName: "ExtensionsTests.remove")!
        defaults.removePersistentDomain(forName: "ExtensionsTests.remove")
        var now = Date(timeIntervalSince1970: 1_790_000_000)
        let water = DrinkWater(defaults: defaults, now: { now })
        water.addGlass()
        water.addGlass()
        water.removeGlass()
        #expect(water.count == 1)
        water.removeGlass()
        water.removeGlass()
        #expect(water.count == 0)
        water.addGlass()
        now += 86_400
        water.removeGlass()   // yesterday's glass is not today's
        #expect(water.count == 0)
        now -= 86_400
        #expect(water.count == 0)
        defaults.removePersistentDomain(forName: "ExtensionsTests.remove")
    }

    @Test func resetTodayZeroesCount() {
        let defaults = UserDefaults(suiteName: "ExtensionsTests.reset")!
        defaults.removePersistentDomain(forName: "ExtensionsTests.reset")
        let water = DrinkWater(defaults: defaults)
        water.addGlass()
        water.addGlass()
        water.resetToday()
        #expect(water.count == 0)
        #expect(DrinkWater(defaults: defaults).count == 0)
        defaults.removePersistentDomain(forName: "ExtensionsTests.reset")
    }

    @Test func waterGoalDefaultsAndClamps() {
        #expect(DrinkWater.goal(stored: nil) == 8)
        #expect(DrinkWater.goal(stored: 5) == 5)
        #expect(DrinkWater.goal(stored: 0) == 1)
        #expect(DrinkWater.goal(stored: 99) == 20)
        let defaults = UserDefaults(suiteName: "ExtensionsTests.goal")!
        defaults.removePersistentDomain(forName: "ExtensionsTests.goal")
        let water = DrinkWater(defaults: defaults)
        #expect(water.goal == 8)
        defaults.set(12, forKey: "extension.drinkWater.goal")
        #expect(water.goal == 12)
        defaults.removePersistentDomain(forName: "ExtensionsTests.goal")
    }

    @Test func waterProgressText() {
        #expect(DrinkWater.progress(count: 1, goal: 8) == "1 of 8 glasses")
        #expect(DrinkWater.progress(count: 10, goal: 8) == "10 of 8 glasses")
        #expect(DrinkWater.fill(count: 0, goal: 8) == 0)
        #expect(DrinkWater.fill(count: 2, goal: 8) == 0.25)
        #expect(DrinkWater.fill(count: 10, goal: 8) == 1)
    }

    @Test func chimeSecondsDefaultAndClamp() {
        #expect(BreakChime.seconds(stored: nil) == 20)
        #expect(BreakChime.seconds(stored: 90) == 90)
        #expect(BreakChime.seconds(stored: 0) == 5)
        #expect(BreakChime.seconds(stored: 99_999) == 3600)
    }

    @Test func durationRowCombinesMinutesAndSeconds() {
        let range = BreakChime.secondsRange
        #expect(DurationRow.total(minutes: 1, seconds: 30, in: range) == 90)
        #expect(DurationRow.total(minutes: 0, seconds: 90, in: range) == 90)
        #expect(DurationRow.total(minutes: 0, seconds: 0, in: range) == 5)
        #expect(DurationRow.total(minutes: 120, seconds: 0, in: range) == 3600)
    }

    @Test func chimeIsCancelledWhenOverlayHides() {
        let chime = BreakChime(defaults: UserDefaults(suiteName: "ExtensionsTests.chime")!)
        chime.overlayWillShow()
        #expect(chime.isScheduled)
        chime.overlayDidHide()
        #expect(!chime.isScheduled)
    }

    @Test func focusPickerSetsCurrentFocus() {
        let defaults = UserDefaults(suiteName: "FocusPickerTests")!
        defaults.removePersistentDomain(forName: "FocusPickerTests")
        let picker = FocusPicker(defaults: defaults)
        defaults.set([" Article ", "", "Email", "Article", "a", "b", "c", "d", "e"], forKey: "extension.focusPicker.list")
        #expect(picker.focuses == ["Article", "Email", "a", "b", "c", "d"])
        picker.pick("Email")
        #expect(defaults.string(forKey: "focus") == "Email")
        #expect(picker.current == "Email")
        defaults.removePersistentDomain(forName: "FocusPickerTests")
    }

    @Test func messagesSkipBlanksAndDontRepeat() {
        let defaults = UserDefaults(suiteName: "MessagesTests")!
        defaults.removePersistentDomain(forName: "MessagesTests")
        let messages = Messages(defaults: defaults)
        #expect(messages.messages.isEmpty)
        messages.overlayWillShow()
        #expect(messages.text == nil)

        defaults.set(["  Breathe ", "", "   ", "Stretch"], forKey: "extension.messages.list")
        #expect(messages.messages == ["Breathe", "Stretch"])
        var last: String?
        for _ in 0..<20 {
            messages.overlayWillShow()
            #expect(messages.text != nil && messages.text != last)
            last = messages.text
        }
        #expect(Messages.pick(from: ["Only"], notRepeating: "Only") == "Only")
        defaults.removePersistentDomain(forName: "MessagesTests")
    }

    private typealias Event = CalendarEvents.Event

    private func event(_ title: String, _ start: Date, id: String? = nil, isAllDay: Bool = false, declined: Bool = false,
                       isFree: Bool = false) -> Event {
        Event(id: "\(id ?? title)|\(start.timeIntervalSince1970)", title: title, start: start, end: start + 1800,
              isAllDay: isAllDay, declined: declined, isFree: isFree)
    }

    @Test func upcomingEventIsEarliestTimedAcceptedBusyWithin20Minutes() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func upcoming(_ events: [Event]) -> String? { CalendarEvents.upcoming(in: events, now: now)?.title }
        #expect(upcoming([]) == nil)
        #expect(upcoming([event("Edge", now + 20 * 60)]) == "Edge")
        #expect(upcoming([event("Late", now + 20 * 60 + 1)]) == nil)
        #expect(upcoming([event("Now", now), event("Started", now - 60)]) == nil)
        #expect(upcoming([event("Holiday", now + 60, isAllDay: true)]) == nil)
        #expect(upcoming([event("Declined", now + 60, declined: true)]) == nil)
        #expect(upcoming([event("Free", now + 60, isFree: true)]) == nil)
        #expect(upcoming([event("Retro", now + 600), event("Standup", now + 300),
                          event("Declined", now + 60, declined: true)]) == "Standup")
    }

    @Test func breakIsDueOncePerLeadWindow() {
        var now = Date(timeIntervalSince1970: 1_790_000_000)
        var handled = Set<String>()
        func due(_ events: [Event]) -> Bool {
            let (due, keys) = CalendarEvents.breakDue(in: events, handled: handled, now: now)
            handled.formUnion(keys)
            return due
        }
        let events = [event("Standup", now + 20 * 60), event("Retro", now + 25 * 60)]
        #expect(due(events))
        #expect(!due(events))
        now += 5 * 60   // Retro comes within 20 minutes while Standup is still ahead
        #expect(!due(events))
        #expect(handled.count == 2)

        // The next occurrence of a recurring event has its own id.
        now += 86_400
        #expect(due([event("Standup", now + 20 * 60, id: "Standup")]))
    }

    @Test func noBreakForShortNoticeOrSkippedEvents() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let soon = CalendarEvents.breakDue(in: [event("Standup", now + 59)], handled: [], now: now)
        #expect(!soon.due && soon.keys == ["b|Standup|\(now.timeIntervalSince1970 + 59)"])
        #expect(CalendarEvents.breakDue(in: [event("Standup", now + 60)], handled: [], now: now).due)
        let skipped = [event("Declined", now + 600, declined: true), event("Holiday", now + 600, isAllDay: true),
                       event("Focus", now + 600, isFree: true)]
        let result = CalendarEvents.breakDue(in: skipped, handled: [], now: now)
        #expect(!result.due && result.keys.isEmpty)
    }

    @Test func inProgressIsStartedAndNotEnded() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let titles = CalendarEvents.inProgress(in: [event("Running", now - 60), event("Starting", now),
                                                    event("Ended", now - 1800), event("Later", now + 1),
                                                    event("Declined", now - 60, declined: true)], now: now).map(\.title)
        #expect(titles == ["Running", "Starting"])
    }

    @Test func breakBeforeDefaultsOnAndTurnsOff() {
        let defaults = UserDefaults(suiteName: "ExtensionsTests.breakBefore")!
        defaults.removePersistentDomain(forName: "ExtensionsTests.breakBefore")
        let calendar = CalendarEvents(defaults: defaults)
        #expect(calendar.breakBefore)
        defaults.set(true, forKey: calendar.enabledKey)
        defaults.set(false, forKey: "extension.calendar.breakBefore")
        #expect(!calendar.breakBefore)
        #expect(!calendar.claimBreak(now: Date()))
        #expect(calendar.claimMeeting(now: Date()) == nil)
        defaults.removePersistentDomain(forName: "ExtensionsTests.breakBefore")
    }

    @Test func handledEventsPersistForADay() {
        let defaults = UserDefaults(suiteName: "ExtensionsTests.handled")!
        defaults.removePersistentDomain(forName: "ExtensionsTests.handled")
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let recent = "b|Standup|\(now.timeIntervalSince1970 + 600)"
        let old = "m|Retro|\(now.timeIntervalSince1970 - 86_401)"
        CalendarEvents(defaults: defaults).markHandled([recent, old], now: now)
        #expect(CalendarEvents(defaults: defaults).handled == [recent])
        defaults.removePersistentDomain(forName: "ExtensionsTests.handled")
    }

    @Test func eventTextRoundsMinutesUp() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(CalendarEvents.menuBarText(event("Standup", now + 11 * 60 + 30), now: now) == "Standup in 12m")
        #expect(CalendarEvents.overlayText(event("Standup", now + 11 * 60 + 30), now: now) == "Standup in 12 minutes")
        #expect(CalendarEvents.overlayText(event("Standup", now + 30), now: now) == "Standup in 1 minute")
        #expect(CalendarEvents.overlayText(event("Standup", now + 60), now: now) == "Standup in 1 minute")
        #expect(CalendarEvents.overlayText(event("Standup", now + 61), now: now) == "Standup in 2 minutes")
    }
}
